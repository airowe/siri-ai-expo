import AppIntents
internal import ExpoAppIntents
import Foundation

/// Identifies an order. Status and arrival are deliberately not stored here, so Siri can only
/// learn them by calling `GetOrderStatusIntent`, as it would for data behind a live API.
struct OrderEntity: AppEntity {
  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Order"
  static let defaultQuery = OrderQuery()

  var id: String

  // `@Property(title:description:)` is new in the 27.3 SDK.
  #if SIRI_AI_PREVIEW
  @Property(title: "Item", description: "What the person ordered, such as running shoes.")
  var item: String
  #else
  @Property(title: "Item")
  var item: String
  #endif

  var synonyms: [String]

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(item)")
  }

  init(record: AppIntentEntityRecord) {
    self.id = record.id
    self.synonyms = record.synonyms
    self.item = record.title
  }

  func matches(_ searchText: String) -> Bool {
    let needle = searchText.lowercased()
    return ([item] + synonyms).contains { $0.lowercased().contains(needle) }
  }
}
