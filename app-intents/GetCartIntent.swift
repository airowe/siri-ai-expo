import AppIntents
import Foundation

/// Answers from a live, authenticated API call, so nothing about the cart is indexed for Siri to answer from instead.
#if SIRI_AI_PREVIEW
@AppIntent(.tool)
#endif
struct GetCartIntent: AppIntent {
  static let title: LocalizedStringResource = "Get Cart"
  static let description = IntentDescription(
    "Tells the person what is in their shopping cart and what it costs."
  )

  static let cartPath = "auth/carts/1"

  func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
    let answer: String
    do {
      let data = try await AuthService.authorizedGet(Self.cartPath)
      answer = describe(try JSONDecoder().decode(Cart.self, from: data))
    } catch AuthError.signedOut {
      ToolOutcome.record("signed out")
      answer = "Open Siri Spike to sign in again."
    } catch {
      ToolOutcome.record("failed: \(error)")
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
