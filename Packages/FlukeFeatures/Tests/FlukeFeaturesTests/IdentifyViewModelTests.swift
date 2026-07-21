import CoreVideo
import FlukeML
import FlukeReleaseB
import Testing

@testable import FlukeFeatures

@MainActor
@Suite("On-device identification state machine")
struct IdentifyViewModelTests {
  @Test("unavailable identification never opens capture")
  func unavailableDoesNoWork() async {
    for capability in [
      IdentifyCapability.unavailable(.localArtifactsUnavailable),
      .unavailable(.serverUnsupported),
    ] {
      let media = RecordingIdentifyMedia()
      let model = IdentifyViewModel(capability: capability, media: media)

      await model.openCamera()

      #expect(media.openCount == 0)
      #expect(model.availability != .ready)
    }
  }

  @Test("camera-only mode opens the live camera without any inference")
  func cameraOnlyOpensWithoutInference() async throws {
    let media = RecordingIdentifyMedia()
    let model = IdentifyViewModel(
      capability: .cameraOnly(.notEnabledForRelease), media: media)

    #expect(model.availability == .cameraOnly(.notEnabledForRelease))
    #expect(model.unavailableMessage == nil)
    #expect(model.matchingNotice != nil)

    await model.openCamera()
    #expect(media.openCount == 1)

    media.yieldWithoutDemand(try Self.frame())
    await Task.yield()
    #expect(model.isIdentifying == false)
    #expect(model.presentation == .idle)
    #expect(model.result == nil)
  }

  @Test("camera-only mode never produces submission evidence")
  func cameraOnlyNeverSuggests() async throws {
    let media = RecordingIdentifyMedia()
    let model = IdentifyViewModel(
      capability: .cameraOnly(.artifactsUnavailable), media: media)
    await model.openCamera()
    media.yieldWithoutDemand(try Self.frame())
    await Task.yield()

    #expect(model.submissionSuggestion == nil)
    #expect(model.matchingNotice != nil)
  }

  @Test("local state maps canonical identities, raw scores, references, and artifact versions")
  func mapsImmutablePresentation() async throws {
    let state = Self.state(prominent: Self.match("J35", whaleID: "canonical-whale"))
    let identifier = RecordingLocalIdentifier(results: [.success(state)])
    let media = RecordingIdentifyMedia()
    let model = IdentifyViewModel(capability: .onDevice(identifier), media: media)
    await model.openCamera()

    await media.yield(try Self.frame())
    await identifier.waitForRequests(1)
    await Self.waitUntil { model.result?.prominent != nil }

    let result = try #require(model.result)
    let prominent = try #require(result.prominent)
    #expect(prominent.whaleID == "canonical-whale")
    #expect(prominent.catalogID == "J35")
    #expect(prominent.score == 0.83)
    #expect(prominent.referencePhotoIDs == ["reference-J35"])
    #expect(result.artifact.manifestVersion == "manifest-v3")
    #expect(result.artifact.modelVersion == "model-v2")
    #expect(result.artifact.indexVersion == "index-v4")
    #expect(result.provisional.count == 2)
    #expect(model.presentation == .stabilized)
  }

  @Test("provisional candidates remain separate from a stabilized result")
  func provisionalCandidates() async throws {
    let identifier = RecordingLocalIdentifier(results: [.success(Self.state(prominent: nil))])
    let media = RecordingIdentifyMedia()
    let model = IdentifyViewModel(capability: .onDevice(identifier), media: media)
    await model.openCamera()

    await media.yield(try Self.frame())
    await identifier.waitForRequests(1)
    await Self.waitUntil { model.result != nil }

    #expect(model.presentation == .provisional)
    #expect(model.result?.prominent == nil)
    #expect(model.result?.provisional.count == 2)
  }

  @Test("Only a stabilized prominent result snapshots validated submission evidence")
  func submissionEvidenceRequiresStabilization() async throws {
    let prominent = Self.match("J35", whaleID: "canonical-whale")
    let identifier = RecordingLocalIdentifier(results: [
      .success(Self.state(prominent: nil)),
      .success(Self.state(prominent: prominent)),
    ])
    let media = RecordingIdentifyMedia()
    let model = IdentifyViewModel(capability: .onDevice(identifier), media: media)
    await model.openCamera()

    await media.yield(try Self.frame())
    await identifier.waitForRequests(1)
    await Self.waitUntil { model.presentation == .provisional }
    #expect(model.submissionSuggestion == nil)

    await media.yield(try Self.frame())
    await identifier.waitForRequests(2)
    await Self.waitUntil { model.presentation == .stabilized }
    let suggestion = try #require(model.submissionSuggestion)

    #expect(suggestion.catalogID == "J35")
    #expect(abs(suggestion.similarityScore - 0.83) < 0.000_001)
    #expect(suggestion.scoreSemantics == LocalIdentificationSuggestion.requiredScoreSemantics)
    #expect(suggestion.matchedReferencePhotoIDs == ["reference-J35"])
  }

  @Test("empty, poor-quality, and unavailable outcomes are first-class")
  func honestNonMatchStates() async throws {
    let cases: [(Result<LocalIdentificationState, Error>, IdentifyPresentation)] = [
      (.success(Self.state(matches: [], prominent: nil)), .unknown),
      (.failure(LocalIdentifierError.preprocessingFailed), .poorQuality),
      (.failure(LocalIdentifierError.modelLoadFailed), .unavailable),
    ]
    for (result, expected) in cases {
      let identifier = RecordingLocalIdentifier(results: [result])
      let media = RecordingIdentifyMedia()
      let model = IdentifyViewModel(capability: .onDevice(identifier), media: media)
      await model.openCamera()
      await media.yield(try Self.frame())
      await identifier.waitForRequests(1)
      await Self.waitUntil { model.presentation == expected }
      model.cameraDidStop()
    }
  }

  @Test("frame inference is sequential with no pending-frame queue")
  func sequentialZeroQueue() async throws {
    let identifier = SuspendedLocalIdentifier(result: Self.state(prominent: nil))
    let media = RecordingIdentifyMedia()
    let model = IdentifyViewModel(capability: .onDevice(identifier), media: media)
    await model.openCamera()

    await media.yield(try Self.frame())
    await identifier.waitUntilRequested()
    media.yieldWithoutDemand(try Self.frame())
    await identifier.resume()
    await Self.waitUntil { model.result != nil }

    #expect(await identifier.requestCount == 1)
    #expect(await identifier.maximumConcurrentRequests == 1)
  }

  @Test("camera stop cancels suspended inference without publishing stale results")
  func stopCancelsInference() async throws {
    let identifier = SuspendedLocalIdentifier(
      result: Self.state(prominent: Self.match("J35", whaleID: "canonical-whale")))
    let media = RecordingIdentifyMedia()
    let model = IdentifyViewModel(capability: .onDevice(identifier), media: media)
    await model.openCamera()
    await media.yield(try Self.frame())
    await identifier.waitUntilRequested()

    model.cameraDidStop()
    await identifier.resume()
    await Task.yield()

    #expect(!model.isIdentifying)
    #expect(model.result == nil)
    #expect(model.presentation == .idle)
  }

  @Test("opening and reopening reset local stabilization before consuming frames")
  func cameraSessionsResetIdentifier() async {
    let identifier = RecordingLocalIdentifier(results: [])
    let media = RecordingIdentifyMedia()
    let model = IdentifyViewModel(capability: .onDevice(identifier), media: media)

    await model.openCamera()
    model.cameraDidStop()
    media.close()
    await model.openCamera()

    #expect(await identifier.resetCount == 2)
  }

  @Test("rapid camera taps share one open and one frame consumer")
  func rapidOpenIsSingleFlight() async {
    let identifier = RecordingLocalIdentifier(results: [])
    let media = SuspendedOpenIdentifyMedia()
    let model = IdentifyViewModel(capability: .onDevice(identifier), media: media)
    let first = Task { await model.openCamera() }
    await media.waitUntilOpenRequested()
    let second = Task { await model.openCamera() }
    for _ in 0..<20 { await Task.yield() }

    #expect(media.openCount == 1)
    media.resumeOpen()
    await first.value
    await second.value

    #expect(media.frameConsumerCount == 1)
    #expect(await identifier.resetCount == 1)
  }

  @Test("reopen after stop waits for a suspended media open to invalidate")
  func reopenDuringSuspendedMediaOpen() async {
    let identifier = RecordingLocalIdentifier(results: [])
    let media = SequencedSuspendedOpenIdentifyMedia()
    let model = IdentifyViewModel(capability: .onDevice(identifier), media: media)
    let staleOpen = Task { await model.openCamera() }
    await media.waitForOpens(1)

    model.cameraDidStop()
    let reopen = Task { await model.openCamera() }
    media.resumeOpen(1, presented: false)
    for _ in 0..<100 where media.openCount < 2 { await Task.yield() }
    guard media.openCount == 2 else {
      await staleOpen.value
      await reopen.value
      Issue.record("Expected the foreground reopen to reach media")
      return
    }
    media.resumeOpen(2, presented: true)
    await staleOpen.value
    await reopen.value

    #expect(media.openCount == 2)
    #expect(media.frameConsumerCount == 1)
    #expect(await identifier.resetCount == 2)
    #expect(model.presentation == .analyzing)
  }

  @Test("old inference cleanup cannot clear a reopened inference indicator")
  func staleInferenceCleanupPreservesNewActivity() async throws {
    let identifier = SequencedSuspendedLocalIdentifier(result: Self.state(prominent: nil))
    let media = RecordingIdentifyMedia()
    let model = IdentifyViewModel(capability: .onDevice(identifier), media: media)
    await model.openCamera()
    await media.yield(try Self.frame())
    await identifier.waitForRequests(1)

    model.cameraDidStop()
    media.close()
    await model.openCamera()
    await media.yield(try Self.frame())
    await identifier.waitForRequests(2)
    #expect(model.isIdentifying)

    await identifier.resumeRequest(1)
    for _ in 0..<20 { await Task.yield() }

    #expect(model.isIdentifying)

    await identifier.resumeRequest(2)
    await Self.waitUntil { !model.isIdentifying }
  }
}

extension IdentifyViewModelTests {
  static let artifact = LocalIdentificationArtifact(
    manifestVersion: "manifest-v3",
    modelVersion: "model-v2",
    indexVersion: "index-v4",
    scoreSemantics: "uncalibrated_similarity_not_probability"
  )

  static func match(_ catalogID: String, whaleID: String) -> LocalMatch {
    LocalMatch(
      catalogID: catalogID,
      whaleID: whaleID,
      score: 0.83,
      rank: 1,
      matchedReferencePhotoIDs: ["reference-\(catalogID)"]
    )
  }

  static func state(
    matches: [LocalMatch]? = nil,
    prominent: LocalMatch?
  ) -> LocalIdentificationState {
    LocalIdentificationState(
      matches: matches ?? [
        match("J35", whaleID: "canonical-whale"),
        match("J27", whaleID: "second-whale"),
      ],
      prominent: prominent,
      artifact: artifact
    )
  }

  static func frame() throws -> CameraFrame {
    var buffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      2,
      2,
      kCVPixelFormatType_32BGRA,
      nil,
      &buffer
    )
    guard status == kCVReturnSuccess, let buffer else {
      throw LocalIdentifierError.invalidPixelBuffer
    }
    return try CameraFrame(pixelBuffer: buffer, orientation: .up)
  }

  static func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
    for _ in 0..<100 where !condition() { await Task.yield() }
  }
}

@MainActor
private final class RecordingIdentifyMedia: IdentifyMediaProviding {
  private let channel = CameraFrameChannel.make()
  var cameraState = PhotoCameraState.available
  private(set) var isCameraPresented = false
  private(set) var openCount = 0
  var frames: AsyncStream<CameraFrame> { channel.frames }

  func openCamera() async {
    openCount += 1
    isCameraPresented = true
  }

  func yield(_ frame: CameraFrame) async {
    for _ in 0..<100 {
      if case .enqueued = channel.continuation.yield(frame) { return }
      await Task.yield()
    }
    Issue.record("Frame consumer never requested demand")
  }

  func yieldWithoutDemand(_ frame: CameraFrame) {
    _ = channel.continuation.yield(frame)
  }

  func close() { isCameraPresented = false }
}

private actor RecordingLocalIdentifier: LocalIdentifying {
  private var results: [Result<LocalIdentificationState, Error>]
  private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
  private(set) var requestCount = 0
  private(set) var resetCount = 0

  init(results: [Result<LocalIdentificationState, Error>]) { self.results = results }

  func resetSession() { resetCount += 1 }

  func identify(frame _: CameraFrame) throws -> LocalIdentificationState {
    requestCount += 1
    let ready = waiters.filter { requestCount >= $0.0 }
    waiters.removeAll { requestCount >= $0.0 }
    for waiter in ready { waiter.1.resume() }
    guard !results.isEmpty else { throw CancellationError() }
    return try results.removeFirst().get()
  }

  func waitForRequests(_ count: Int) async {
    guard requestCount < count else { return }
    await withCheckedContinuation { waiters.append((count, $0)) }
  }
}

@MainActor
private final class SuspendedOpenIdentifyMedia: IdentifyMediaProviding {
  private let channel = CameraFrameChannel.make()
  private var continuations: [CheckedContinuation<Void, Never>] = []
  private var waiters: [CheckedContinuation<Void, Never>] = []
  let cameraState = PhotoCameraState.available
  private(set) var isCameraPresented = false
  private(set) var openCount = 0
  private(set) var frameConsumerCount = 0
  var frames: AsyncStream<CameraFrame> {
    frameConsumerCount += 1
    return channel.frames
  }

  func openCamera() async {
    openCount += 1
    let ready = waiters
    waiters = []
    for waiter in ready { waiter.resume() }
    await withCheckedContinuation { continuations.append($0) }
    isCameraPresented = true
  }

  func waitUntilOpenRequested() async {
    guard openCount == 0 else { return }
    await withCheckedContinuation { waiters.append($0) }
  }

  func resumeOpen() {
    let pending = continuations
    continuations = []
    for continuation in pending { continuation.resume() }
  }
}

@MainActor
private final class SequencedSuspendedOpenIdentifyMedia: IdentifyMediaProviding {
  private let channel = CameraFrameChannel.make()
  private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
  private var outcomes: [Int: Bool] = [:]
  private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
  let cameraState = PhotoCameraState.available
  private(set) var isCameraPresented = false
  private(set) var openCount = 0
  private(set) var frameConsumerCount = 0
  var frames: AsyncStream<CameraFrame> {
    frameConsumerCount += 1
    return channel.frames
  }

  func openCamera() async {
    openCount += 1
    let request = openCount
    let ready = waiters.filter { request >= $0.0 }
    waiters.removeAll { request >= $0.0 }
    for waiter in ready { waiter.1.resume() }
    await withCheckedContinuation { continuations[request] = $0 }
    isCameraPresented = outcomes.removeValue(forKey: request) ?? false
  }

  func waitForOpens(_ count: Int) async {
    guard openCount < count else { return }
    await withCheckedContinuation { waiters.append((count, $0)) }
  }

  func resumeOpen(_ request: Int, presented: Bool) {
    outcomes[request] = presented
    continuations.removeValue(forKey: request)?.resume()
  }
}

private actor SuspendedLocalIdentifier: LocalIdentifying {
  let result: LocalIdentificationState
  private var continuation: CheckedContinuation<Void, Never>?
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private(set) var requestCount = 0
  private(set) var maximumConcurrentRequests = 0
  private var concurrentRequests = 0

  init(result: LocalIdentificationState) { self.result = result }

  func identify(frame _: CameraFrame) async -> LocalIdentificationState {
    requestCount += 1
    concurrentRequests += 1
    maximumConcurrentRequests = max(maximumConcurrentRequests, concurrentRequests)
    let ready = waiters
    waiters = []
    for waiter in ready { waiter.resume() }
    await withCheckedContinuation { continuation = $0 }
    concurrentRequests -= 1
    return result
  }

  func waitUntilRequested() async {
    guard requestCount == 0 else { return }
    await withCheckedContinuation { waiters.append($0) }
  }

  func resume() {
    continuation?.resume()
    continuation = nil
  }
}

private actor SequencedSuspendedLocalIdentifier: LocalIdentifying {
  private let result: LocalIdentificationState
  private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
  private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
  private(set) var requestCount = 0

  init(result: LocalIdentificationState) { self.result = result }

  func identify(frame _: CameraFrame) async -> LocalIdentificationState {
    requestCount += 1
    let request = requestCount
    let ready = waiters.filter { request >= $0.0 }
    waiters.removeAll { request >= $0.0 }
    for waiter in ready { waiter.1.resume() }
    await withCheckedContinuation { continuations[request] = $0 }
    return result
  }

  func waitForRequests(_ count: Int) async {
    guard requestCount < count else { return }
    await withCheckedContinuation { waiters.append((count, $0)) }
  }

  func resumeRequest(_ request: Int) {
    continuations.removeValue(forKey: request)?.resume()
  }
}
