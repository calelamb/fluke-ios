import FlukeFeatures

enum SubmissionQueueBridgeError: Error, Equatable {
  case notIntegrated
}

/// Compile-safe boundary for Task 2 only. Task 3 must replace this value at
/// the RootScene injection point with its durable SubmissionQueue adapter.
nonisolated struct DeferredSubmissionQueueBridge: QueuedLogbookProviding,
  AccountAssociationClearing
{
  func queuedEntries() async -> [QueuedLogbookEntry] { [] }

  func clearAccountAssociation() async throws {
    throw SubmissionQueueBridgeError.notIntegrated
  }
}
