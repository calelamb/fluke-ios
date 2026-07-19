import CoreVideo
import FlukeML
import Testing

@testable import FlukeFeatures

@MainActor
@Suite("On-device identification state machine")
struct IdentifyViewModelTests {
  @Test("disabled and unavailable identification never open capture")
  func unavailableDoesNoWork() async {
    for capability in [
      IdentifyCapability.disabled,
      .unavailable(.localArtifactsUnavailable),
      .unavailable(.serverUnsupported),
    ] {
      let media = RecordingIdentifyMedia()
      let model = IdentifyViewModel(capability: capability, media: media)

      await model.openCamera()

      #expect(media.openCount == 0)
      #expect(model.availability != .ready)
    }
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
}

extension IdentifyViewModelTests {
  static let artifact = LocalIdentificationArtifact(
    manifestVersion: "manifest-v3",
    modelVersion: "model-v2",
    indexVersion: "index-v4"
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
}

private actor RecordingLocalIdentifier: LocalIdentifying {
  private var results: [Result<LocalIdentificationState, Error>]
  private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
  private(set) var requestCount = 0

  init(results: [Result<LocalIdentificationState, Error>]) { self.results = results }

  func identify(frame _: CameraFrame) throws -> LocalIdentificationState {
    requestCount += 1
    let ready = waiters.filter { requestCount >= $0.0 }
    waiters.removeAll { requestCount >= $0.0 }
    ready.forEach { $0.1.resume() }
    guard !results.isEmpty else { throw CancellationError() }
    return try results.removeFirst().get()
  }

  func waitForRequests(_ count: Int) async {
    guard requestCount < count else { return }
    await withCheckedContinuation { waiters.append((count, $0)) }
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
    ready.forEach { $0.resume() }
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
