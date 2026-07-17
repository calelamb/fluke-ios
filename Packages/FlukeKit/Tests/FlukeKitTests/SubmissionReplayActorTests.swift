import Foundation
import FlukeReleaseB
import Testing

@Suite("Submission replay")
struct SubmissionReplayActorTests {
  @Test("A successful flush removes the queue row and photo files")
  func flushSuccess() async throws {
    let (queue, _) = try await makeQueue()
    let replay = SubmissionReplayActor(queue: queue, service: ReplayService())

    await replay.flush()

    #expect(try await queue.list().isEmpty)
  }

  @Test("Partial upload retains only failed photos and receipt, then retries without duplication")
  func partialThenSuccess() async throws {
    let (queue, value) = try await makeQueue(photoCount: 2)
    let service = ReplayService(results: [
      .failure(SubmissionServiceError.partial(
        receipt: SubmissionReceipt(id: "created", photoUploadToken: "token"),
        failedPhotoIndices: [1]
      )),
      .success(SubmissionReceipt(id: "created", photoUploadToken: "token")),
    ])
    let replay = SubmissionReplayActor(queue: queue, service: service)

    await replay.flush()
    let retained = try #require(try await queue.list().first)
    #expect(retained.payload.existingReceipt?.id == "created")
    #expect(try await queue.photoBytes(for: retained).count == 1)
    await replay.flush()

    #expect(try await queue.list().isEmpty)
    #expect(await service.payloads.map { $0.existingReceipt?.id } == [nil, "created"])
    let photoIDs = await service.photoIDs
    #expect(photoIDs.count == 2)
    #expect(photoIDs[1] == [photoIDs[0][1]])
    #expect(value.id == retained.id)
  }

  @Test("Transient failures increment attempts and the third becomes failed")
  func failureThreshold() async throws {
    let (queue, value) = try await makeQueue()
    let replay = SubmissionReplayActor(
      queue: queue,
      service: ReplayService(results: Array(repeating: .failure(ReplayService.Failure.offline), count: 3))
    )

    await replay.flush()
    await replay.flush()
    await replay.flush()

    let failed = try #require(try await queue.list().first)
    #expect(failed.id == value.id)
    #expect(failed.attempts == 3)
    #expect(failed.state == .failed)
  }

  @Test("Concurrent flush calls coalesce into one in-flight submission")
  func concurrentFlushCoalesces() async throws {
    let (queue, _) = try await makeQueue()
    let service = BlockingReplayService()
    let replay = SubmissionReplayActor(queue: queue, service: service)

    let first = Task { await replay.flush() }
    await service.waitUntilCalled()
    let second = Task { await replay.flush() }
    await Task.yield()
    #expect(await service.callCount == 1)
    await service.release()
    await first.value
    await second.value

    #expect(await service.callCount == 1)
    #expect(try await queue.list().isEmpty)
  }

  private func makeQueue(photoCount: Int = 1) async throws -> (SubmissionQueue, QueuedSubmissionValue) {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let queue = try SubmissionQueue(directory: directory, inMemory: true)
    let payload = try SubmissionValidator.validate(.fixture(photoCount: photoCount))
    let photos = (0..<photoCount).map { ProcessedPhoto.fixture(UInt8($0)) }
    return (queue, try await queue.enqueue(payload: payload, photos: photos))
  }
}

private actor BlockingReplayService: SubmissionServiceProtocol {
  private(set) var callCount = 0
  private var submitContinuation: CheckedContinuation<Void, Never>?
  private var callWaiters: [CheckedContinuation<Void, Never>] = []

  func submit(payload: SubmissionPayload, photos: [ProcessedPhoto]) async throws -> SubmissionReceipt {
    callCount += 1
    let waiters = callWaiters
    callWaiters = []
    waiters.forEach { $0.resume() }
    await withCheckedContinuation { submitContinuation = $0 }
    return SubmissionReceipt(id: "created", photoUploadToken: "token")
  }

  func waitUntilCalled() async {
    if callCount > 0 { return }
    await withCheckedContinuation { callWaiters.append($0) }
  }

  func release() { submitContinuation?.resume(); submitContinuation = nil }
}

private actor ReplayService: SubmissionServiceProtocol {
  enum Failure: Error, Sendable { case offline }
  private var results: [Result<SubmissionReceipt, any Error & Sendable>]
  private(set) var payloads: [SubmissionPayload] = []
  private(set) var photoIDs: [[UUID]] = []

  init(results: [Result<SubmissionReceipt, any Error & Sendable>] = [
    .success(SubmissionReceipt(id: "created", photoUploadToken: "token"))
  ]) { self.results = results }

  func submit(payload: SubmissionPayload, photos: [ProcessedPhoto]) async throws -> SubmissionReceipt {
    payloads = payloads + [payload]
    photoIDs = photoIDs + [photos.map(\.idempotencyID)]
    return try results.removeFirst().get()
  }
}
