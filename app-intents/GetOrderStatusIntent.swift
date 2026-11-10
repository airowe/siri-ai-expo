import AppIntents
internal import ExpoAppIntents

/// Read-only, answered from Swift so it needs no JavaScript. The attribute is conditional so the
/// same declaration builds on SDKs without the tool trait, which also shows whether a tool can stay
/// in an app that deploys below iOS 27.3.
#if SIRI_AI_PREVIEW
@AppIntent(.tool)
#endif
struct GetOrderStatusIntent: AppIntent {
  static let title: LocalizedStringResource = "Get Order Status"
  static let description = IntentDescription(
    "Tells the person where one of their orders is and when it should arrive."
  )

  @Parameter(title: "Order", description: "The order the person is asking about.")
  var order: OrderEntity

  func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
    let record = try await AppIntentEntityStore.shared.entities(ofKind: "order", matching: [order.id]).first
    let status = record?.metadata["status"] ?? "unknown"
    let arrival = record?.metadata["arrival"] ?? "unknown"
    let answer = "\(order.item) is \(status), arriving \(arrival)."
    return .result(value: answer, dialog: "\(answer)")
  }
}
