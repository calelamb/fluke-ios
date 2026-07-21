import FlukeFeatures
import FlukeReleaseB
import Foundation

nonisolated struct DeferredSubmissionQueueBridge: QueuedLogbookProviding,
  AccountAssociationClearing
{
  let queue: SubmissionQueue

  func queuedEntries() async -> [QueuedLogbookEntry] {
    guard let values = try? await queue.list() else { return [] }
    return values.map {
      QueuedLogbookEntry(
        id: $0.id.uuidString,
        observedAt: $0.payload.observedAt,
        locationName: $0.payload.locationName
      )
    }
  }

  func clearAccountAssociation() async throws {
    try await queue.clearAccountAssociation()
  }
}
