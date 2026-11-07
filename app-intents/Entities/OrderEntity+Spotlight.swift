import AppIntents
@preconcurrency import CoreSpotlight
internal import ExpoAppIntents

@available(iOS 18.0, macOS 15.0, *)
extension OrderEntity: AppIntentEntityRecordConvertible {}

@available(iOS 18.0, macOS 15.0, *)
extension OrderEntity: IndexedEntity {
  var attributeSet: CSSearchableItemAttributeSet {
    let attributes = defaultAttributeSet
    attributes.displayName = item
    attributes.title = item
    attributes.contentDescription = "\(status), \(arrival)"
    attributes.keywords = ["order", "delivery", item] + synonyms
    return attributes
  }
}
