import Foundation
import FlukeFeatures
import FlukeKit
import FlukeReleaseB
import Testing

@MainActor
@Suite("Submit state machine")
struct SubmitViewModelTests {
  @Test("Offline submit queues once and presents an honest receipt")
  func queuesOffline() async {
    let queue = RecordingSubmissionQueue()
    let model = SubmitViewModel(service: SubmitService(error: APIError.offline), queue: queue)
    model.email = "observer@example.com"
    model.photos = [.fixture]

    await model.submit()
    await model.submit()

    #expect(model.state == .queued)
    #expect(await queue.enqueuedCount == 1)
  }

  @Test("A dirty form requires explicit discard")
  func dirtyDismissal() {
    let model = SubmitViewModel(service: SubmitService(), queue: RecordingSubmissionQueue())
    model.locationName = "Lime Kiln"
    #expect(model.dismissal == .requiresConfirmation)
  }

  @Test("Signed-in submit omits email while anonymous validates it")
  func authEmailBehavior() async {
    let service = SubmitService()
    let signedIn = SubmitViewModel(service: service, queue: RecordingSubmissionQueue(), isSignedIn: true)
    signedIn.email = "bad"
    signedIn.photos = [.fixture]
    await signedIn.submit()
    #expect(signedIn.state == .success)
    #expect(await service.payloads.first?.observerEmail == nil)

    let anonymous = SubmitViewModel(service: SubmitService(), queue: RecordingSubmissionQueue())
    anonymous.email = "bad"
    anonymous.photos = [.fixture]
    await anonymous.submit()
    #expect(anonymous.state == .validation(.email))
  }

  @Test("Photo selection is capped at five and disabled capability is honest")
  func photoCapAndCapability() {
    let model = SubmitViewModel(
      service: SubmitService(), queue: RecordingSubmissionQueue(), submissionsEnabled: false
    )
    model.addPhotos(Array(repeating: .fixture, count: 6))
    #expect(model.photos.count == 5)
    #expect(model.disabledMessage?.contains("unavailable") == true)
  }
}

private actor SubmitService: SubmissionServiceProtocol {
  let error: (any Error & Sendable)?
  private(set) var payloads: [SubmissionPayload] = []
  init(error: (any Error & Sendable)? = nil) { self.error = error }
  func submit(payload: SubmissionPayload, photos: [ProcessedPhoto]) async throws -> SubmissionReceipt {
    payloads = payloads + [payload]
    if let error { throw error }
    return SubmissionReceipt(id: "sighting", photoUploadToken: "token")
  }
}

private actor RecordingSubmissionQueue: SubmissionQueueProtocol {
  private(set) var enqueuedCount = 0
  func list() async throws -> [QueuedSubmissionValue] { [] }
  func enqueue(payload: SubmissionPayload, photos: [ProcessedPhoto]) async throws -> QueuedSubmissionValue {
    enqueuedCount += 1
    return QueuedSubmissionValue(
      id: UUID(), payload: payload, photoFileNames: [], state: .queued,
      attempts: 0, createdAt: Date()
    )
  }
  func retry(id: UUID) async throws {}
  func discard(id: UUID) async throws {}
}

private extension ProcessedPhoto {
  static let fixture = ProcessedPhoto(bytes: Data(repeating: 1, count: 10), fileName: "photo.jpg")
}
