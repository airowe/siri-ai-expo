import AppIntents
import Foundation

/// Answers from a live API call, so nothing about the cart is indexed for Siri to answer from instead.
#if SIRI_AI_PREVIEW
@AppIntent(.tool)
#endif
struct GetCartIntent: AppIntent {
  static let title: LocalizedStringResource = "Get Cart"
  static let description = IntentDescription(
    "Tells the person what is in their shopping cart and what it costs."
  )

  func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
    let answer: String
    do {
      answer = describe(try await CartService.fetchCart())
    } catch {
      answer = "Couldn't reach the cart service."
    }
    return .result(value: answer, dialog: "\(answer)")
  }

  private func describe(_ cart: Cart) -> String {
    let total = cart.total.formatted(.currency(code: "USD"))
    let titles = cart.products.map(\.title).joined(separator: ", ")
    return "Your cart has \(cart.totalProducts) products, \(total): \(titles)."
  }
}

struct Cart: Decodable {
  struct Product: Decodable {
    let title: String
    let quantity: Int
  }

  let products: [Product]
  let total: Double
  let totalProducts: Int
}

enum CartService {
  static let cartURL = URL(string: "https://dummyjson.com/carts/1")!
  static let timeout: TimeInterval = 10

  static func fetchCart() async throws -> Cart {
    var request = URLRequest(url: cartURL)
    request.timeoutInterval = timeout
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
      throw URLError(.badServerResponse)
    }
    return try JSONDecoder().decode(Cart.self, from: data)
  }
}
