#if SIRI_AI_PREVIEW
import AppIntents
internal import ExpoAppIntents

/// Siri fills this in from the request without calling a query.
@AppEntity(.generable)
struct OrderSearch: TransientAppEntity {
  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Order Search"

  @Property(title: "Keyword", description: "A word describing the item, such as shoes.")
  var keyword: String

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(keyword)")
  }

  init() {}
}

@AppIntent(.tool)
struct SearchOrdersIntent: AppIntent {
  static let title: LocalizedStringResource = "Search Orders"
  static let description = IntentDescription("Finds the person's orders that match a keyword.")

  @Parameter(title: "Search", description: "What to look for in the person's orders.")
  var search: OrderSearch

  func perform() async throws -> some ReturnsValue<[OrderEntity]> {
    .result(value: try await OrderQuery().entities(matching: search.keyword))
  }
}
#endif
