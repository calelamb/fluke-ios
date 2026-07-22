import FlukeFeatures
import FlukeKit
import FlukeReleaseB
import Foundation
import Testing

@MainActor
@Suite("Submit state machine")
struct SubmitViewModelTests {
  @Test("Valid submit is durable before replay and never waits for the network")
  func queuesBeforeReplay() async {
    let queue = RecordingSubmissionQueue()
    let replay = BlockingReplaySignal()
    let model = SubmitViewModel(
      queue: queue,
      replayQueuedSubmissions: { await replay.signal() }
    )
    model.email = "observer@example.com"
    model.photos = [.fixture]

    await model.submit()
    await replay.waitUntilSignaled()

    #expect(model.state == .queued)
    #expect(await queue.enqueuedCount == 1)
    #expect(await replay.signalCount == 1)
    await replay.release()
  }

  @Test("Submit queues once and presents an honest receipt")
  func queuesOffline() async {
    let queue = RecordingSubmissionQueue()
    let model = SubmitViewModel(queue: queue)
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
    let model = SubmitViewModel(queue: RecordingSubmissionQueue())
    model.locationName = "Lime Kiln"
    #expect(model.dismissal == .requiresConfirmation)
  }

  @Test("Coordinate and observation date changes make the form dirty")
  func coordinateAndDateDirtyDismissal() {
    let initialDate = Date(timeIntervalSince1970: 1_700_000_000)
    let coordinateModel = SubmitViewModel(
      queue: RecordingSubmissionQueue(), observedAt: initialDate
    )
    #expect(coordinateModel.dismissal == .allowed)
    coordinateModel.latitude += 0.001
    #expect(coordinateModel.dismissal == .requiresConfirmation)

    let dateModel = SubmitViewModel(
      queue: RecordingSubmissionQueue(), observedAt: initialDate
    )
    dateModel.observedAt = initialDate.addingTimeInterval(60)
    #expect(dateModel.dismissal == .requiresConfirmation)
  }

  @Test("Signed-in submit uses hidden account email while anonymous validates it")
  func authEmailBehavior() async {
    let signedInQueue = RecordingSubmissionQueue()
    let signedIn = SubmitViewModel(
      queue: signedInQueue,
      isSignedIn: true,
      signedInObserverEmail: "account@example.com"
    )
    signedIn.email = "bad"
    signedIn.photos = [.fixture]
    await signedIn.submit()
    #expect(signedIn.state == .queued)
    #expect(await signedInQueue.lastPayload?.observerEmail == "account@example.com")

    let anonymous = SubmitViewModel(queue: RecordingSubmissionQueue())
    anonymous.email = "bad"
    anonymous.photos = [.fixture]
    await anonymous.submit()
    #expect(anonymous.state == .validation(.email))
  }

  @Test("Photo selection is capped at five and disabled capability is honest")
  func photoCapAndCapability() {
    let model = SubmitViewModel(
      queue: RecordingSubmissionQueue(), submissionsEnabled: false
    )
    model.addPhotos(
      (0..<6).map { index in
        ProcessedPhoto(bytes: Data([UInt8(index)]), fileName: "\(index).jpg")
      })
    #expect(model.photos.count == 5)
    #expect(model.disabledMessage?.contains("unavailable") == true)
  }

  @Test("Queue-first submit saves the complete sighting and all photos")
  func queuesCompleteSubmission() async {
    let queue = RecordingSubmissionQueue()
    let model = validModel(queue: queue, photoCount: 2)

    await model.submit()

    #expect(model.state == .queued)
    #expect(model.dismissal == .allowed)
    #expect(await queue.lastPhotos.count == 2)
    #expect(await queue.lastPayload?.existingReceipt == nil)
  }

  @Test("Durable save failure is explicit and retryable")
  func queueFailure() async {
    let queue = RecordingSubmissionQueue(error: TestFailure.queue)
    let model = validModel(queue: queue)

    await model.submit()

    #expect(model.state == .failed("Fluke couldn't safely save this sighting. Please try again."))
    #expect(model.dismissal == .requiresConfirmation)
  }

  @Test("Durable save failure can retry with the same idempotency identifier")
  func queueFailureRetry() async {
    let queue = FailOnceSubmissionQueue()
    let model = validModel(queue: queue)

    await model.submit()
    #expect(model.state == .failed("Fluke couldn't safely save this sighting. Please try again."))
    await model.submit()

    #expect(model.state == .queued)
    #expect(model.failureMessage == nil)
    #expect(model.dismissal == .allowed)
    let payloads = await queue.payloads
    #expect(payloads.map(\.clientSubmissionID).count == 2)
    #expect(Set(payloads.map(\.clientSubmissionID)).count == 1)
  }

  @Test("Route evidence and nullable ecotype are copied into every retry payload")
  func preservesRouteEvidence() async throws {
    let suggestion = try #require(
      LocalIdentificationSuggestion(
        catalogID: "J35",
        similarityScore: 0.82,
        scoreSemantics: LocalIdentificationSuggestion.requiredScoreSemantics,
        manifestVersion: "manifest",
        modelVersion: "model",
        indexVersion: "index",
        matchedReferencePhotoIDs: ["ref-2", "ref-1"]
      ))
    let queue = RecordingSubmissionQueue()
    let model = SubmitViewModel(
      queue: queue,
      ecotypeGuess: nil,
      localIdentification: suggestion
    )
    model.email = "observer@example.com"
    model.photos = [.fixture]

    await model.submit()

    #expect(await queue.lastPayload?.localIdentification == suggestion)
    #expect(await queue.lastPayload?.ecotypeGuess == nil)
  }

  @Test("Validation state identifies the invalid field")
  func validationFocus() async {
    let model = validModel(queue: RecordingSubmissionQueue())
    model.latitude = 91
    await model.submit()
    #expect(model.state == .validation(.latitude))
    #expect(model.validationField == .location)
    #expect(SubmissionFormField.forValidationError(.longitude) == .location)
    #expect(SubmissionFormField.forValidationError(.observedAt) == .observedAt)
    #expect(SubmissionFormField.forValidationError(.groupSize) == .groupSize)
    #expect(SubmissionFormField.forValidationError(.notes) == .notes)
    #expect(SubmissionFormField.forValidationError(.locationName) == .locationName)
    #expect(SubmissionFormField.forValidationError(.email) == .email)
    #expect(SubmissionFormField.forValidationError(.photos) == .photos)
  }

  @Test("Duplicate tap while durable save is suspended enqueues once")
  func duplicateTapSuppression() async {
    let queue = BlockingSubmissionQueue()
    let model = validModel(queue: queue)
    let first = Task { await model.submit() }
    await queue.waitUntilCalled()

    await model.submit()
    #expect(await queue.callCount == 1)
    await queue.release()
    await first.value
    #expect(model.state == .queued)
  }

  @Test("Signed-in form hides observer email")
  func hidesSignedInEmail() {
    let signedIn = SubmitViewModel(
      queue: RecordingSubmissionQueue(), isSignedIn: true,
      signedInObserverEmail: "account@example.com"
    )
    let anonymous = SubmitViewModel(queue: RecordingSubmissionQueue())
    #expect(!signedIn.showsObserverEmail)
    #expect(anonymous.showsObserverEmail)
  }

  @Test("Signed-in presentation without an account email fails closed to email entry")
  func signedInMissingEmailShowsEntry() async {
    let queue = RecordingSubmissionQueue()
    let model = SubmitViewModel(
      queue: queue, isSignedIn: true,
      signedInObserverEmail: nil
    )
    #expect(model.showsObserverEmail)
    model.email = "fallback@example.com"
    model.photos = [.fixture]

    await model.submit()

    #expect(model.state == .queued)
    #expect(await queue.lastPayload?.observerEmail == "fallback@example.com")
  }

  @Test("Repeated picker interactions consume only new asset IDs and never duplicate photos")
  func pickerSelectionDeduplication() {
    let tracker = PhotoSelectionTracker()
    let firstBatch = tracker.consuming(["asset-a", "asset-b"])
    #expect(firstBatch.indices == [0, 1])
    let secondBatch = firstBatch.tracker.consuming(["asset-a", "asset-b", "asset-c"])
    #expect(secondBatch.indices == [2])
    #expect(secondBatch.tracker.consuming(["asset-a", "asset-c"]).indices.isEmpty)

    let first = ProcessedPhoto(
      bytes: Data([1]), fileName: "first.jpg",
      idempotencyID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    )
    let second = ProcessedPhoto(
      bytes: Data([1]), fileName: "duplicate-with-new-id.jpg",
      idempotencyID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    )
    let model = SubmitViewModel(queue: RecordingSubmissionQueue())
    model.addPhotos([first])
    model.addPhotos([first, second])
    #expect(model.photos.map(\.idempotencyID) == [first.idempotencyID])
  }

  @Test("Coordinate selection clamps latitude and wraps longitude")
  func coordinateSelection() {
    #expect(
      SubmissionCoordinate(latitude: 95, longitude: 190) == .init(latitude: 90, longitude: -170))
    #expect(
      SubmissionCoordinate(latitude: -95, longitude: -190) == .init(latitude: -90, longitude: 170))
    let coarse = SubmissionCoordinate(latitude: 48.123_456, longitude: -123.987_654)
    #expect(coarse.latitude == 48.12)
    #expect(coarse.longitude == -123.99)
  }

  @Test("Photo and camera failures map to bounded safe copy")
  func photoFailurePresentation() {
    #expect(PhotoSelectionPresentation.message(for: .loadFailed).contains("selected photo"))
    #expect(PhotoSelectionPresentation.message(for: .processingFailed).contains("JPEG or HEIC"))
    #expect(
      PhotoSelectionPresentation.cameraState(for: .denied)
        == .unavailable(
          "Camera access is off. You can enable it in Settings or choose a photo instead."
        ))
    #expect(PhotoSelectionPresentation.cameraState(for: .restricted).isUnavailable)
    #expect(PhotoSelectionPresentation.cameraResult(data: nil) == .failure(.processingFailed))
    #expect(PhotoSelectionPresentation.cameraResult(data: Data([1])) == .success(Data([1])))
  }

  private func validModel(
    queue: any SubmissionQueueProtocol,
    photoCount: Int = 1
  ) -> SubmitViewModel {
    let model = SubmitViewModel(queue: queue)
    model.email = "observer@example.com"
    model.photos = Array(repeating: .fixture, count: photoCount)
    return model
  }
}

private enum TestFailure: Error, Sendable { case queue }

private actor RecordingSubmissionQueue: SubmissionQueueProtocol {
  let error: (any Error & Sendable)?
  private(set) var enqueuedCount = 0
  private(set) var lastPayload: SubmissionPayload?
  private(set) var lastPhotos: [ProcessedPhoto] = []
  init(error: (any Error & Sendable)? = nil) { self.error = error }
  func list() async throws -> [QueuedSubmissionValue] { [] }
  func enqueue(payload: SubmissionPayload, photos: [ProcessedPhoto]) async throws
    -> QueuedSubmissionValue
  {
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

private actor FailOnceSubmissionQueue: SubmissionQueueProtocol {
  private(set) var payloads: [SubmissionPayload] = []
  func list() async throws -> [QueuedSubmissionValue] { [] }
  func enqueue(payload: SubmissionPayload, photos: [ProcessedPhoto]) async throws
    -> QueuedSubmissionValue
  {
    payloads = payloads + [payload]
    if payloads.count == 1 { throw TestFailure.queue }
    return QueuedSubmissionValue(
      id: UUID(), payload: payload, photoFileNames: [], state: .queued,
      attempts: 0, createdAt: Date())
  }
  func retry(id: UUID) async throws {}
  func discard(id: UUID) async throws {}
}

private actor BlockingSubmissionQueue: SubmissionQueueProtocol {
  private(set) var callCount = 0
  private var enqueueContinuation: CheckedContinuation<Void, Never>?
  private var waiters: [CheckedContinuation<Void, Never>] = []
  func list() async throws -> [QueuedSubmissionValue] { [] }
  func enqueue(payload: SubmissionPayload, photos: [ProcessedPhoto]) async throws
    -> QueuedSubmissionValue
  {
    callCount += 1
    let current = waiters
    waiters = []
    for continuation in current { continuation.resume() }
    await withCheckedContinuation { enqueueContinuation = $0 }
    return QueuedSubmissionValue(
      id: UUID(), payload: payload, photoFileNames: [], state: .queued,
      attempts: 0, createdAt: Date())
  }
  func waitUntilCalled() async {
    if callCount > 0 { return }
    await withCheckedContinuation { waiters.append($0) }
  }
  func release() {
    enqueueContinuation?.resume()
    enqueueContinuation = nil
  }
  func retry(id: UUID) async throws {}
  func discard(id: UUID) async throws {}
}

private actor BlockingReplaySignal {
  private(set) var signalCount = 0
  private var continuation: CheckedContinuation<Void, Never>?
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func signal() async {
    signalCount += 1
    let current = waiters
    waiters = []
    current.forEach { $0.resume() }
    await withCheckedContinuation { continuation = $0 }
  }

  func waitUntilSignaled() async {
    if signalCount > 0 { return }
    await withCheckedContinuation { waiters.append($0) }
  }

  func release() {
    continuation?.resume()
    continuation = nil
  }
}

extension PhotoCameraState {
  fileprivate var isUnavailable: Bool {
    if case .unavailable = self { return true }
    return false
  }
}

extension ProcessedPhoto {
  fileprivate static let fixture = ProcessedPhoto(
    bytes: Data(repeating: 1, count: 10), fileName: "photo.jpg")
}
