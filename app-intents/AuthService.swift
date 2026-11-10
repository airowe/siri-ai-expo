import Foundation
import Security

struct AuthTokens: Codable {
  let accessToken: String
  let refreshToken: String
}

enum AuthError: Error {
  case signedOut
  case keychain(OSStatus)
  case rejected(Int)
}

/// Signs in to DummyJSON's public demo account and keeps its tokens in the Keychain, so a tool can
/// call protected endpoints while the app is closed.
enum AuthService {
  static let baseURL = URL(string: "https://dummyjson.com")!
  static let demoUsername = "emilys"
  static let demoPassword = "emilyspass"
  static let accessTokenLifetimeMinutes = 1
  static let refreshEnabled = true
  static let timeout: TimeInterval = 10
  private static let expiredStatuses: Set<Int> = [401, 403]

  static func signIn() async throws {
    let tokens: AuthTokens = try await post("auth/login", body: [
      "username": demoUsername,
      "password": demoPassword,
      "expiresInMins": accessTokenLifetimeMinutes,
    ])
    try TokenStore.save(tokens)
  }

  static func signOut() {
    TokenStore.clear()
  }

  /// GETs a protected path. On an expired token, refreshes once and retries.
  static func authorizedGet(_ path: String) async throws -> Data {
    guard let tokens = try TokenStore.load() else { throw AuthError.signedOut }
    let (data, status) = try await get(path, token: tokens.accessToken)
    if status == 200 {
      ToolOutcome.record("used saved token")
      return data
    }
    guard expiredStatuses.contains(status) else { throw AuthError.rejected(status) }
    guard refreshEnabled, let fresh = try? await refresh(tokens) else { throw AuthError.signedOut }
    let (retried, retriedStatus) = try await get(path, token: fresh.accessToken)
    guard retriedStatus == 200 else { throw AuthError.signedOut }
    ToolOutcome.record("refreshed after \(status)")
    return retried
  }

  private static func refresh(_ tokens: AuthTokens) async throws -> AuthTokens {
    let fresh: AuthTokens = try await post("auth/refresh", body: [
      "refreshToken": tokens.refreshToken,
      "expiresInMins": accessTokenLifetimeMinutes,
    ])
    try TokenStore.save(fresh)
    return fresh
  }

  private static func get(_ path: String, token: String) async throws -> (Data, Int) {
    var request = URLRequest(url: baseURL.appending(path: path))
    request.timeoutInterval = timeout
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    let (data, response) = try await URLSession.shared.data(for: request)
    return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
  }

  private static func post<Response: Decodable>(_ path: String, body: [String: Any]) async throws -> Response {
    var request = URLRequest(url: baseURL.appending(path: path))
    request.httpMethod = "POST"
    request.timeoutInterval = timeout
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 200 else { throw AuthError.rejected(status) }
    return try JSONDecoder().decode(Response.self, from: data)
  }
}

/// Readable after the first unlock, so a tool can use it while the phone is locked.
enum TokenStore {
  private static let service = "com.adamrowe.sirispike.auth"
  private static let account = "tokens"

  private static var baseQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }

  static func save(_ tokens: AuthTokens) throws {
    SecItemDelete(baseQuery as CFDictionary)
    var item = baseQuery
    item[kSecValueData as String] = try JSONEncoder().encode(tokens)
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let status = SecItemAdd(item as CFDictionary, nil)
    guard status == errSecSuccess else { throw AuthError.keychain(status) }
  }

  static func load() throws -> AuthTokens? {
    var query = baseQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else { throw AuthError.keychain(status) }
    return try JSONDecoder().decode(AuthTokens.self, from: data)
  }

  static func clear() {
    SecItemDelete(baseQuery as CFDictionary)
  }
}

/// What the last tool call did, shown in the app so a test can tell a refresh from a fresh token.
enum ToolOutcome {
  private static let key = "lastToolOutcome"

  static func record(_ outcome: String) {
    let time = Date().formatted(date: .omitted, time: .standard)
    UserDefaults.standard.set("\(outcome) at \(time)", forKey: key)
  }

  static var last: String {
    UserDefaults.standard.string(forKey: key) ?? "none"
  }
}
