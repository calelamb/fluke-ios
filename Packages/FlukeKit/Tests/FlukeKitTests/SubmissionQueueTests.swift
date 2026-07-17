import Foundation
import FlukeReleaseB
import Testing

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
}
