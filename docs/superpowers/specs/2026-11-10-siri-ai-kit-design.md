# SiriAIKit design

Date: 2026-11-10. Status: approved in conversation, awaiting written review.

## Why

The siri-ai-expo spike showed that Siri AI tools (App Intents with `@AppIntent(.tool)`) work in an Expo app. It also showed that each app has to hand-write the same supporting code:

- calling its backend from inside a tool, with timeouts and replies that suit Siri
- keeping login tokens usable when the app is closed and the phone is locked, including refreshing an expired token mid-request
- testing that Siri actually calls the tools, which needs a lot of setup around Apple's Siri Evaluations framework

Apple's App Intents covers how Siri finds and calls tools. It leaves the inside of a tool and the testing workflow to each app.

SiriAIKit packages what the spike proved as a Swift package. Native apps can use it now. Expo apps get it through a later Expo package (`expo-siri-ai`), which wraps it and adds the Expo-only setup.

## Goals

- **`SiriAIKit` library:** backend calls, token storage and refresh, and spoken failure replies for code inside App Intents tools.
- **`SiriAIEvalKit` library:** helpers that cut the setup for Siri Evaluations tests.
- **`siri-ai-eval` command-line tool:** summarizes evaluation results, and reports runs the harness scored as incomplete separately from real failures.
- **Every behaviour proven by the spike stays proven:** the example app's cart, token-expiry and negative-control checks pass on a device using the kit.

## Non-goals

- **Declaring intents, entities or tools.** Those must be compiled into the app target for Apple's metadata extraction to find them. The kit is called from them.
- **Expo-specific setup** (the preview build flag, the 27.3 deployment target, keeping the evaluation target and skills bundle through prebuild). That belongs in the later `expo-siri-ai` package.
- **Donations, action discovery and code generation.** Parked for later.
- **Sign-in flows.** The app signs in its own way (OAuth, passwords, Sign in with Apple) and hands the tokens to the kit.
- **Retrying on network errors, caching, uploads.**

## Anti-goals

- **No looping refresh, and no tool that fails silently.** Every failure ends in a reply the person hears.
- **Nothing that implies Apple made it.** The README states the package isn't affiliated with Apple. The name stays SiriAIKit until Apple objects or ships something similar.
- **No dependency on Expo or React Native** in any target.

## Constraints

- **Swift Package Manager needs `Package.swift` at the repo root,** so the package gets its own repo, `siri-ai-kit`. It's created private at `~/Projects/siri-ai-kit` and published only when the owner says so.
- **Toolchain:** Xcode 27.3 beta (27C5020n), Swift 6.4.2, Swift 6 language mode with strict concurrency.
- **Platforms:**
  - `SiriAIKit`: iOS 17+. It also declares macOS 15+, so the package resolves for the macOS-only CLI.
  - `SiriAIEvalKit`: iOS 27.3, on a device. It imports `SiriEvaluations`, `Evaluations`, `AppIntentsTesting` and `XCTest`. Xcode 27.3 ships these frameworks for devices only, not for the Simulator.
  - `siri-ai-eval`: macOS 15+.
- **Testing follows TDD:** write a failing test, then the implementation. Tests live in SwiftPM test targets under `Tests/`. That's SwiftPM's layout; the colocated `*.spec.ts` rule applies to the later TypeScript package.
- **Where tests run:**
  - `SiriAIKitTests` run on the iOS Simulator (`xcodebuild test -scheme SiriAIKit -destination 'platform=iOS Simulator,name=<device>'`). A Keychain item with an accessibility class lives in the data protection keychain, which an unsigned `swift test` run on a Mac may not be allowed to use.
  - `SiriAIEvalSummaryTests` run with `swift test` on the Mac.

## Package layout

```
siri-ai-kit/
  Package.swift
  Sources/
    SiriAIKit/
    SiriAIEvalKit/
    SiriAIEvalSummary/       results parsing, used by the CLI and testable on a Mac
    siri-ai-eval/            executable: argument parsing and printing only
  Tests/
    SiriAIKitTests/
    SiriAIEvalSummaryTests/
      Fixtures/              real .xcevalresult files from the spike, with personal details removed
  Example/                   the spike app's tools and evaluations, ported to the kit
  README.md
  LICENSE (MIT)
```

The CLI's parsing lives in a library target (`SiriAIEvalSummary`), so it can be unit tested without spawning a process.

## SiriAIKit API

```swift
public struct Tokens: Codable, Sendable, Equatable {
  public var accessToken: String
  public var refreshToken: String
}

public protocol TokenStore: Sendable {
  func load() throws(ToolError) -> Tokens?
  func save(_ tokens: Tokens) throws(ToolError)
  func clear()
}

public struct KeychainTokenStore: TokenStore {
  public init(service: String, account: String = "tokens",
              accessibility: KeychainAccessibility = .afterFirstUnlockThisDeviceOnly)
}

public actor TokenAuthenticator {
  public init(store: some TokenStore,
              expiredStatuses: Set<Int> = [401],
              refresh: @escaping @Sendable (Tokens) async throws -> Tokens)
}

public struct ToolHTTPClient: Sendable {
  public init(baseURL: URL, timeout: Duration = .seconds(10),
              session: URLSession = .shared, auth: TokenAuthenticator? = nil,
              outcomes: ToolOutcomeLog = .standard)
  public func get<Response: Decodable>(_ path: String, as: Response.Type) async throws(ToolError) -> Response
  public func send<Body: Encodable, Response: Decodable>(_ method: HTTPMethod, _ path: String,
                                                        body: Body, as: Response.Type) async throws(ToolError) -> Response
}

public enum ToolError: Error, Equatable {
  case signedOut, timedOut, unreachable, rejected(status: Int), invalidResponse
  public func reply(appName: String, overrides: ToolReplies = .default) -> String
}

public struct ToolOutcomeLog: Sendable {
  public static let standard: ToolOutcomeLog          // UserDefaults.standard
  public var last: String { get }                      // e.g. "refreshed after 401 at 11:34:11"
}
```

### Behaviour

- **Fresh token:** sends `Authorization: Bearer <access>` and decodes the response. Records "used saved token".
- **Expired token** (status in `expiredStatuses`): `TokenAuthenticator` calls `refresh` once, saves the new tokens, and retries once. On success it records "refreshed after <status>". If the refresh throws, or the retry is rejected again, the call throws `.signedOut` and records "signed out".
- **Concurrent expiry:** calls that hit an expired token while a refresh is in flight wait for that refresh instead of starting their own. The actor holds the in-flight refresh task.
- **No stored tokens:** throws `.signedOut` without touching the network.
- **Timeout:** `.timedOut`. **Other transport errors:** `.unreachable`. **Other non-2xx statuses:** `.rejected(status:)`. **Decode failures:** `.invalidResponse`.
- **Keychain read failure** (for example before the first unlock): throws `.signedOut`, and records the Keychain status in the outcome so it can be diagnosed.
- **Default replies:**
  - `.signedOut`: "Open <App> to sign in again."
  - `.timedOut` and `.unreachable`: "Couldn't reach <App> right now."
  - `.rejected` and `.invalidResponse`: "<App> couldn't do that right now."
  - Each can be overridden through `ToolReplies`.
- **Public APIs need no authenticator.** Pass `auth: nil`, and the client sends no `Authorization` header and never refreshes.

### Tests (SiriAIKitTests)

- Network responses come from a `URLProtocol` stub registered on a custom `URLSession`.
- Token stores in the client tests use an in-memory `TokenStore`. The Keychain store has its own round-trip test.
- Parameterized cases:
  - Fresh token used as-is.
  - 401 → one refresh → retry succeeds. Asserts the refresh count is 1 and the new tokens are saved.
  - Refresh throws → `.signedOut`.
  - Retry is also 401 → `.signedOut`, refresh count still 1.
  - 403 when `expiredStatuses` is `[401]` → `.rejected(403)`.
  - No tokens → `.signedOut`, no request sent.
  - Timeout → `.timedOut`.
  - Bad JSON → `.invalidResponse`.
  - Two concurrent calls on an expired token → exactly one refresh, both succeed.
  - Keychain: save, load and clear round trip, and `kSecAttrAccessible` equals the configured value.
  - Each outcome string is recorded for its case.
  - `reply(appName:)` default and override text.

## SiriAIEvalKit API

```swift
@available(iOS 27.3, *)
public struct SiriAppHarness: Sendable {
  public init(bundleIdentifier: String, readyWhen: ReadySignal, timeout: Duration = .seconds(90))
  @MainActor public func launchAndWaitUntilReady() throws       // throws with the label's text on timeout
  @MainActor public func lastToolOutcome() -> String?             // reads "siri-ai-tool-outcome"
}

public enum ReadySignal: Sendable {
  case label(_ identifier: String, contains: String)
  case labelBegins(_ identifier: String, with: String)
}

@available(iOS 27.3, *)
public struct ToolEvaluation: Evaluation {
  public init(name: String, harness: SiriAppHarness,
              before: BeforeRun = .none,                   // .none or .waitFor(Duration)
              dataset: SiriScenarioLoader)
}

extension SiriScenarioLoader {
  public static func repeating(times: Int, _ scenario: () -> SiriScenario) -> SiriScenarioLoader
}

public func expectAllPass(_ metrics: SiriMetric...) throws      // .intents → intentsAllPass, .siriResponse → siriResponseAllPass
```

- **`ToolEvaluation.subject(from:)`:** launches and waits until ready, applies `before`, runs the scenario through `SiriService`, then prints `[siri-ai-eval] outcome: <text>` read via `lastToolOutcome()`.
- **`expectAllPass`** reads `EvaluationContext.current.result` and records one failing `#expect` per metric whose mean is below 1, naming the metric.
- **Tool outcome readback:** the test runner can't read the app's storage. The app shows `ToolOutcomeLog.standard.last` in an element with accessibility identifier `siri-ai-tool-outcome`, refreshed at least once a second. SiriAIKit ships `ToolOutcomeView` (SwiftUI, compiled in DEBUG only) for native apps.

### Risks to check first

- **Linking `XCTest` from a library target.** Using `XCUIApplication` from a library rather than a test target needs XCTest linked into a non-test target. The first task proves this builds for a device before anything else is written. If it can't, `SiriAppHarness` ships as source files the app's evaluation target compiles directly.

### Tests

- `SiriAIEvalKit` has no unit tests, because its frameworks don't exist on the Simulator or the Mac. CI and the build check prove it compiles for `generic/platform=iOS`.
- **Behaviour is proven on a device** by the example app's evaluations:
  - the cart tool, 5 runs
  - the expired-token refresh, 5 runs
  - the negative control with refresh disabled, which must fail its reply check

## siri-ai-eval CLI

```
swift run siri-ai-eval summarize <path.xcresult> [--json] [--fail-on any|real]
```

- Runs `xcrun xcresulttool export attachments` into a temporary folder and reads each `.xcevalresult`.
- For each evaluation, prints its name and, per run:
  - tool calls with yes or no
  - Siri's reply
  - the reply check result
  - the recorded tool outcome, if the test log contains it
  - **incomplete**, when the harness reports "the run ended before all of its results arrived"
- Prints two pass rates: Apple's (incomplete counts as a failure) and real (incomplete runs excluded).
- **Exit status:** `--fail-on any` (the default) exits non-zero on any failure, matching Apple's score. `--fail-on real` exits non-zero only on real failures.

### Tests (SiriAIEvalSummaryTests)

Fixtures are the spike's `.xcevalresult` JSON files, with device names and IDs replaced. Each case asserts exact counts and pass rates:
- all-pass cart run
- order tool skipped (intents fail, reply pass)
- negative control (reply fail)
- mixed run with incomplete results
- malformed file (clear error naming the file)

## Example app

`Example/` holds the spike's cart tool and evaluations rewritten against the kit, as an Xcode project, with no Expo. The spike's `AuthService` is replaced by `KeychainTokenStore`, `TokenAuthenticator` and `ToolHTTPClient`. Its evaluations use `ToolEvaluation`.

The demo backend stays DummyJSON's public test account with a one-minute token.

**Done means:** on the iPhone,
- the cart evaluation passes 5 of 5 on real pass rate
- the expired-token evaluation records "refreshed after 401" in every completed run
- the refresh-disabled control fails its reply check

## Left to the builder

- Names of internal types and files.
- Exact formatting of the CLI's text output, as long as it shows every field listed above.
- Whether `ToolOutcomeView` polls or observes `UserDefaults`.

## Open after this spec

- Packaging for Expo (`expo-siri-ai`): a podspec over these sources, the config plugin, and a React Native outcome component.
- Donations and action discovery.
