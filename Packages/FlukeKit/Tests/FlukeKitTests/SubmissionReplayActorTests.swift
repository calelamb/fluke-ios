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

  private func makeQueue(photoCount: Int = 1) async throws -> (SubmissionQueue, QueuedSubmissionValue) {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let queue = try SubmissionQueue(directory: directory, inMemory: true)
    let payload = try SubmissionValidator.validate(.fixture(photoCount: photoCount))
    let photos = (0..<photoCount).map { ProcessedPhoto.fixture(UInt8($0)) }
    return (queue, try await queue.enqueue(payload: payload, photos: photos))
  }
}

private actor ReplayService: SubmissionServiceProtocol {
  enum Failure: Error, Sendable { case offline }
  private var results: [Result<SubmissionReceipt, any Error & Sendable>]
  private(set) var payloads: [SubmissionPayload] = []

  init(results: [Result<SubmissionReceipt, any Error & Sendable>] = [
    .success(SubmissionReceipt(id: "created", photoUploadToken: "token"))
  ]) { self.results = results }

  func submit(payload: SubmissionPayload, photos: [ProcessedPhoto]) async throws -> SubmissionReceipt {
    payloads = payloads + [payload]
    return try results.removeFirst().get()
  }
}
