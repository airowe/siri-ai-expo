import AppIntents
@preconcurrency import CoreSpotlight
internal import ExpoAppIntents

struct OrderQuery: EntityStringQuery {
  func entities(for identifiers: [String]) async throws -> [OrderEntity] {
    try await AppIntentEntityStore.shared.entities(ofKind: "order", matching: identifiers)
      .map(OrderEntity.init(record:))
  }

  func suggestedEntities() async throws -> [OrderEntity] {
    try await AppIntentEntityStore.shared.entities(ofKind: "order").map(OrderEntity.init(record:))
  }

  func entities(matching string: String) async throws -> [OrderEntity] {
    try await suggestedEntities().filter { $0.matches(string) }
  }
}

@available(iOS 18.0, macOS 15.0, *)
extension OrderQuery: EnumerableEntityQuery {
  func allEntities() async throws -> [OrderEntity] {
    try await suggestedEntities()
  }
}

#if compiler(>=6.4)
@available(iOS 27.0, macOS 27.0, *)
extension OrderQuery: IndexedEntityQuery {
  func reindexEntities(
    for identifiers: [OrderEntity.ID],
    indexDescription: CSSearchableIndexDescription
  ) async throws {
    try await AppEntityIdentifierRegistry.shared.updateIndexFromCatalog(kind: "order", matching: identifiers)
  }

  func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
    try await AppEntityIdentifierRegistry.shared.replaceIndexFromCatalog(kind: "order")
  }
}
#endif
