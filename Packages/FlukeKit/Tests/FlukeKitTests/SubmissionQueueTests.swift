import Foundation
import SwiftData
import Testing
@testable import FlukeReleaseB

@Suite("Durable submission queue")
struct SubmissionQueueTests {
  @Test("Enqueue persists immutable payload and photo bytes; discard removes both")
  func enqueueAndDiscard() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let queue = try SubmissionQueue(directory: directory, inMemory: true)
    let payload = try SubmissionValidator.validate(.fixture(photoCount: 1))

    let value = try await queue.enqueue(payload: payload, photos: [.fixture(7)])
    #expect(try await queue.list() == [value])
    #expect(try await queue.photoBytes(for: value).map(\.count) == [32])

    try await queue.discard(id: value.id)
    #expect(try await queue.list().isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path()).isEmpty)
  }

  @Test("Failed photo write is atomic and leaves no queue row")
  func atomicFailure() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let queue = try SubmissionQueue(
      directory: directory,
      inMemory: true,
      photoStore: QueuedPhotoStore(directory: directory, failAfterWrites: 0)
    )
    let payload = try SubmissionValidator.validate(.fixture(photoCount: 1))

    await #expect(throws: QueuedPhotoStoreError.injectedFailure) {
      try await queue.enqueue(payload: payload, photos: [.fixture(1)])
    }
    #expect(try await queue.list().isEmpty)
  }

  @Test("Failure after atomic move removes the final file and temporary bytes")
  func postMoveFailureLeavesNoBytes() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let queue = try SubmissionQueue(
      directory: directory,
      inMemory: true,
      photoStore: QueuedPhotoStore(directory: directory, failAfterMoveAtIndex: 0)
    )
    let payload = try SubmissionValidator.validate(.fixture(photoCount: 1))

    await #expect(throws: QueuedPhotoStoreError.injectedFailure) {
      try await queue.enqueue(payload: payload, photos: [.fixture(1)])
    }

    #expect(try await queue.list().isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path()).isEmpty)
  }

  @Test("Discard removal failure preserves the durable row for retry")
  func discardFailurePreservesRow() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let store = QueuedPhotoStore(directory: directory, failRemoval: true)
    let queue = try SubmissionQueue(directory: directory, inMemory: true, photoStore: store)
    let payload = try SubmissionValidator.validate(.fixture(photoCount: 1))
    let value = try await queue.enqueue(payload: payload, photos: [.fixture(1)])

    await #expect(throws: QueuedPhotoStoreError.injectedFailure) {
      try await queue.discard(id: value.id)
    }

    #expect(try await queue.list().isEmpty)
    #expect(try await queue.photoBytes(for: value).count == 1)
  }

  @Test("A discarding tombstone is hidden and finishes cleanup after relaunch")
  func relaunchRecoversDiscardingTombstone() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let payload = try SubmissionValidator.validate(.fixture(photoCount: 1))
    let value: QueuedSubmissionValue
    do {
      let queue = try SubmissionQueue(
        directory: directory,
        photoStore: QueuedPhotoStore(directory: directory, failRemoval: true)
      )
      value = try await queue.enqueue(payload: payload, photos: [.fixture(1)])
      await #expect(throws: QueuedPhotoStoreError.injectedFailure) {
        try await queue.discard(id: value.id)
      }
      #expect(try await queue.list().isEmpty)
    }

    let relaunched = try SubmissionQueue(directory: directory)
    try await relaunched.reconcileStorage()

    #expect(try await relaunched.list().isEmpty)
    #expect(try photoFiles(in: directory).isEmpty)
  }

  @Test("Failed enqueue save rolls back and relaunch removes staged private bytes")
  func relaunchRecoversFailedEnqueueCleanup() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let payload = try SubmissionValidator.validate(.fixture(photoCount: 1))
    do {
      let queue = try SubmissionQueue(
        directory: directory,
        photoStore: QueuedPhotoStore(directory: directory, failRemoval: true),
        saveContext: { _ in throw InjectedSaveError() }
      )

      await #expect(throws: InjectedSaveError.self) {
        try await queue.enqueue(payload: payload, photos: [.fixture(1)])
      }
      #expect(try await queue.list().isEmpty)
      #expect(try photoFiles(in: directory).count == 1)
    }

    let relaunched = try SubmissionQueue(directory: directory)
    try await relaunched.reconcileStorage()

    #expect(try await relaunched.list().isEmpty)
    #expect(try photoFiles(in: directory).isEmpty)
  }

  @Test("Legacy queued filenames derive a stable photo idempotency identity")
  func legacyPhotoIdentity() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let name = "11111111-1111-1111-1111-111111111111-0.jpg"
    try Data(repeating: 1, count: 8).write(to: directory.appending(path: name))
    let store = QueuedPhotoStore(directory: directory)

    let first = try await store.read([name]).first?.idempotencyID
    let second = try await store.read([name]).first?.idempotencyID

    #expect(first != nil)
    #expect(first == second)
  }

  @Test("Account cleanup removes observer association without discarding wildlife data")
  func clearsAccountAssociation() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let queue = try SubmissionQueue(directory: directory, inMemory: true)
    let payload = try SubmissionValidator.validate(.fixture(photoCount: 1))
    _ = try await queue.enqueue(payload: payload, photos: [.fixture(1)])

    try await queue.clearAccountAssociation()

    #expect(try await queue.list().first?.payload.observerEmail == nil)
  }

  @Test("Retry finds a persisted entry after relaunch and resets its bounded attempt state")
  func retryAfterRelaunch() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let payload = try SubmissionValidator.validate(.fixture(photoCount: 1))
    let id: UUID
    do {
      let queue = try SubmissionQueue(directory: directory)
      let value = try await queue.enqueue(payload: payload, photos: [.fixture(1)])
      id = value.id
      try await queue.recordFailure(id: id)
      try await queue.recordFailure(id: id)
      try await queue.recordFailure(id: id)
      #expect(try await queue.list().first?.state == .failed)
      #expect(try await queue.list().first?.attempts == 3)
    }

    let relaunched = try SubmissionQueue(directory: directory)
    try await relaunched.retry(id: id)

    #expect(try await relaunched.list().first?.state == .queued)
    #expect(try await relaunched.list().first?.attempts == 0)
  }

  @Test("Concurrent retries remain idempotent and actor-isolated")
  func concurrentRetries() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let queue = try SubmissionQueue(directory: directory, inMemory: true)
    let payload = try SubmissionValidator.validate(.fixture(photoCount: 1))
    let value = try await queue.enqueue(payload: payload, photos: [.fixture(1)])
    try await queue.recordFailure(id: value.id)

    try await withThrowingTaskGroup(of: Void.self) { group in
      for _ in 0..<8 {
        group.addTask {
          try await queue.retry(id: value.id)
        }
      }
      try await group.waitForAll()
    }

    let entries = try await queue.list()
    #expect(entries.count == 1)
    #expect(entries.first?.id == value.id)
    #expect(entries.first?.state == .queued)
    #expect(entries.first?.attempts == 0)
  }

  @Test("Lookup observes rows inserted and deleted by a second context after a warm fetch")
  func lookupObservesSecondContextChanges() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let payload = try SubmissionValidator.validate(.fixture(photoCount: 1))
    let firstQueue = try SubmissionQueue(directory: directory)
    let first = try await firstQueue.enqueue(payload: payload, photos: [.fixture(1)])
    try await firstQueue.retry(id: first.id)

    let secondQueue = try SubmissionQueue(directory: directory)
    let second = try await secondQueue.enqueue(payload: payload, photos: [.fixture(2)])

    try await firstQueue.retry(id: second.id)
    try await firstQueue.recordFailure(id: second.id)
    #expect(try await firstQueue.list().first(where: { $0.id == second.id })?.attempts == 1)

    try await secondQueue.discard(id: first.id)
    await #expect(throws: SubmissionQueueError.missingEntry) {
      try await firstQueue.recordFailure(id: first.id)
    }
  }

  @Test("Discard rolls back a failed final delete save and reconciliation can finish cleanup")
  func discardDeleteSaveRollback() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let savePlan = SaveFailurePlan(failingCalls: [3])
    let queue = try SubmissionQueue(
      directory: directory,
      saveContext: savePlan.save
    )
    let payload = try SubmissionValidator.validate(.fixture(photoCount: 1))
    let value = try await queue.enqueue(payload: payload, photos: [.fixture(1)])

    await #expect(throws: InjectedSaveError.self) {
      try await queue.discard(id: value.id)
    }
    #expect(try await queue.list().isEmpty)
    #expect(try photoFiles(in: directory).isEmpty)

    try await queue.reconcileStorage()
    #expect(try await queue.list().isEmpty)
    #expect(savePlan.completedCallCount == 4)
  }

  @Test("Reconciliation rolls back a failed tombstone delete save and retries safely")
  func reconciliationDeleteSaveRollback() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let payload = try SubmissionValidator.validate(.fixture(photoCount: 1))
    do {
      let queue = try SubmissionQueue(
        directory: directory,
        photoStore: QueuedPhotoStore(directory: directory, failRemoval: true)
      )
      let value = try await queue.enqueue(payload: payload, photos: [.fixture(1)])
      await #expect(throws: QueuedPhotoStoreError.injectedFailure) {
        try await queue.discard(id: value.id)
      }
    }

    let savePlan = SaveFailurePlan(failingCalls: [1])
    let relaunched = try SubmissionQueue(
      directory: directory,
      saveContext: savePlan.save
    )
    await #expect(throws: InjectedSaveError.self) {
      try await relaunched.reconcileStorage()
    }
    #expect(try await relaunched.list().isEmpty)
    #expect(try photoFiles(in: directory).isEmpty)

    try await relaunched.reconcileStorage()
    #expect(try await relaunched.list().isEmpty)
    #expect(savePlan.completedCallCount == 2)
  }
}

private struct InjectedSaveError: Error {}

private final class SaveFailurePlan: @unchecked Sendable {
  private let lock = NSLock()
  private let failingCalls: Set<Int>
  private var callCount = 0

  init(failingCalls: Set<Int>) {
    self.failingCalls = failingCalls
  }

  func save(_ context: ModelContext) throws {
    lock.lock()
    callCount += 1
    let shouldFail = failingCalls.contains(callCount)
    lock.unlock()
    if shouldFail { throw InjectedSaveError() }
    try context.save()
  }

  var completedCallCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return callCount
  }
}

private func photoFiles(in directory: URL) throws -> [String] {
  try FileManager.default.contentsOfDirectory(atPath: directory.path())
    .filter { $0.hasSuffix(".jpg") }
}
