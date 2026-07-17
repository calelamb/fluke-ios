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
    #expect(model.dismissal == .allowed)
    #expect(await queue.enqueuedCount == 1)
  }

  @Test("A dirty form requires explicit discard")
  func dirtyDismissal() {
    let model = SubmitViewModel(service: SubmitService(), queue: RecordingSubmissionQueue())
    model.locationName = "Lime Kiln"
    #expect(model.dismissal == .requiresConfirmation)
  }

  @Test("Signed-in submit uses hidden account email while anonymous validates it")
  func authEmailBehavior() async {
    let service = SubmitService()
    let signedIn = SubmitViewModel(
      service: service,
      queue: RecordingSubmissionQueue(),
      isSignedIn: true,
      signedInObserverEmail: "account@example.com"
    )
    signedIn.email = "bad"
    signedIn.photos = [.fixture]
    await signedIn.submit()
    #expect(signedIn.state == .success)
    #expect(await service.payloads.first?.observerEmail == "account@example.com")

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

  @Test("Partial upload queues only failed photos and terminal state dismisses cleanly")
  func partialQueuesAndDismisses() async {
    let receipt = SubmissionReceipt(id: "created", photoUploadToken: "token")
    let queue = RecordingSubmissionQueue()
    let model = validModel(
      service: SubmitService(error: SubmissionServiceError.partial(
        receipt: receipt, failedPhotoIndices: [1]
      )),
      queue: queue,
      photoCount: 2
    )

    await model.submit()

    #expect(model.state == .partial)
    #expect(model.dismissal == .allowed)
    #expect(await queue.lastPhotos.count == 1)
    #expect(await queue.lastPayload?.existingReceipt == receipt)
  }

  @Test("Partial upload queue failure is explicit and retryable")
  func partialQueueFailure() async {
    let queue = RecordingSubmissionQueue(error: TestFailure.queue)
    let service = SubmitService(error: SubmissionServiceError.partial(
      receipt: SubmissionReceipt(id: "created", photoUploadToken: "token"),
      failedPhotoIndices: [0]
    ))
    let model = validModel(service: service, queue: queue)

    await model.submit()

    #expect(model.state == .failed("The sighting was saved, but failed photos could not be queued."))
  }

  @Test("Generic failure can retry to success")
  func genericFailureRetry() async {
    let service = SequencedSubmitService(results: [
      .failure(TestFailure.service),
      .success(SubmissionReceipt(id: "created", photoUploadToken: "token")),
    ])
    let model = validModel(service: service, queue: RecordingSubmissionQueue())

    await model.submit()
    #expect(model.state == .failed("Fluke couldn't submit this sighting. Please try again."))
    await model.submit()

    #expect(model.state == .success)
    #expect(model.dismissal == .allowed)
    #expect(await service.callCount == 2)
  }

  @Test("Validation state identifies the invalid field")
  func validationFocus() async {
    let model = validModel(service: SubmitService(), queue: RecordingSubmissionQueue())
    model.latitude = 91
    await model.submit()
    #expect(model.state == .validation(.latitude))
  }

  @Test("Duplicate tap while request is suspended submits once")
  func duplicateTapSuppression() async {
    let service = BlockingSubmitService()
    let model = validModel(service: service, queue: RecordingSubmissionQueue())
    let first = Task { await model.submit() }
    await service.waitUntilCalled()

    await model.submit()
    #expect(await service.callCount == 1)
    await service.release()
    await first.value
    #expect(model.state == .success)
  }

  @Test("Signed-in form hides observer email")
  func hidesSignedInEmail() {
    let signedIn = SubmitViewModel(
      service: SubmitService(), queue: RecordingSubmissionQueue(), isSignedIn: true
    )
    let anonymous = SubmitViewModel(service: SubmitService(), queue: RecordingSubmissionQueue())
    #expect(!signedIn.showsObserverEmail)
    #expect(anonymous.showsObserverEmail)
  }

  @Test("Coordinate selection clamps latitude and wraps longitude")
  func coordinateSelection() {
    #expect(SubmissionCoordinate(latitude: 95, longitude: 190) == .init(latitude: 90, longitude: -170))
    #expect(SubmissionCoordinate(latitude: -95, longitude: -190) == .init(latitude: -90, longitude: 170))
  }

  @Test("Photo and camera failures map to bounded safe copy")
  func photoFailurePresentation() {
    #expect(PhotoSelectionPresentation.message(for: .loadFailed).contains("selected photo"))
    #expect(PhotoSelectionPresentation.message(for: .processingFailed).contains("JPEG or HEIC"))
    #expect(PhotoSelectionPresentation.cameraState(for: .denied) == .unavailable(
      "Camera access is off. You can enable it in Settings or choose a photo instead."
    ))
    #expect(PhotoSelectionPresentation.cameraState(for: .restricted).isUnavailable)
  }

  private func validModel(
    service: any SubmissionServiceProtocol,
    queue: any SubmissionQueueProtocol,
    photoCount: Int = 1
  ) -> SubmitViewModel {
    let model = SubmitViewModel(service: service, queue: queue)
    model.email = "observer@example.com"
    model.photos = Array(repeating: .fixture, count: photoCount)
    return model
  }
}

private enum TestFailure: Error, Sendable { case service, queue }

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
  let error: (any Error & Sendable)?
  private(set) var enqueuedCount = 0
  private(set) var lastPayload: SubmissionPayload?
  private(set) var lastPhotos: [ProcessedPhoto] = []
  init(error: (any Error & Sendable)? = nil) { self.error = error }
  func list() async throws -> [QueuedSubmissionValue] { [] }
  func enqueue(payload: SubmissionPayload, photos: [ProcessedPhoto]) async throws -> QueuedSubmissionValue {
    if let error { throw error }
    enqueuedCount += 1
    lastPayload = payload
    lastPhotos = photos
    return QueuedSubmissionValue(
      id: UUID(), payload: payload, photoFileNames: [], state: .queued,
      attempts: 0, createdAt: Date()
    )
  }
  func retry(id: UUID) async throws {}
  func discard(id: UUID) async throws {}
}

private actor SequencedSubmitService: SubmissionServiceProtocol {
  private var results: [Result<SubmissionReceipt, any Error & Sendable>]
  private(set) var callCount = 0
  init(results: [Result<SubmissionReceipt, any Error & Sendable>]) { self.results = results }
  func submit(payload: SubmissionPayload, photos: [ProcessedPhoto]) async throws -> SubmissionReceipt {
    callCount += 1
    return try results.removeFirst().get()
  }
}

private actor BlockingSubmitService: SubmissionServiceProtocol {
  private(set) var callCount = 0
  private var submitContinuation: CheckedContinuation<Void, Never>?
  private var waiters: [CheckedContinuation<Void, Never>] = []
  func submit(payload: SubmissionPayload, photos: [ProcessedPhoto]) async throws -> SubmissionReceipt {
    callCount += 1
    let current = waiters
    waiters = []
    current.forEach { $0.resume() }
    await withCheckedContinuation { submitContinuation = $0 }
    return SubmissionReceipt(id: "created", photoUploadToken: "token")
  }
  func waitUntilCalled() async {
    if callCount > 0 { return }
    await withCheckedContinuation { waiters.append($0) }
  }
  func release() { submitContinuation?.resume(); submitContinuation = nil }
}

private extension PhotoCameraState {
  var isUnavailable: Bool {
    if case .unavailable = self { return true }
    return false
  }
}

private extension ProcessedPhoto {
  static let fixture = ProcessedPhoto(bytes: Data(repeating: 1, count: 10), fileName: "photo.jpg")
}
