import AppIntents
internal import ExpoAppIntents
import Foundation

struct OrderEntity: AppEntity {
  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Order"
  static let defaultQuery = OrderQuery()

  var id: String

  // `@Property(title:description:)` is new in the 27.3 SDK.
  #if SIRI_AI_PREVIEW
  @Property(title: "Item", description: "What the person ordered, such as running shoes.")
  var item: String

  @Property(title: "Status", description: "Where the order is now: preparing, shipped, out for delivery, or delivered.")
  var status: String

  @Property(title: "Arrival", description: "When the order is expected to arrive, in plain language.")
  var arrival: String
  #else
  @Property(title: "Item")
  var item: String

  @Property(title: "Status")
  var status: String

  @Property(title: "Arrival")
  var arrival: String
  #endif

  var synonyms: [String]

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(item)", subtitle: "\(status), \(arrival)")
  }

  init(record: AppIntentEntityRecord) {
    self.id = record.id
    self.synonyms = record.synonyms
    self.item = record.title
    self.status = record.metadata["status"] ?? "unknown"
    self.arrival = record.metadata["arrival"] ?? "unknown"
  }

  func matches(_ searchText: String) -> Bool {
    let needle = searchText.lowercased()
    return ([item, status] + synonyms).contains { $0.lowercased().contains(needle) }
  }
}
