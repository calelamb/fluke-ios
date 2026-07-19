import AVFoundation
import CoreVideo
import FlukeML
import Testing

@testable import FlukeFeatures

@Suite("Live identification camera")
struct IdentifyCameraPipelineTests {
  @Test("video output uses native bi-planar YUV and discards late frames")
  func videoOutputPolicy() {
    #expect(
      IdentifyVideoOutputConfiguration.pixelFormat
        == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
    #expect(IdentifyVideoOutputConfiguration.discardsLateFrames)
  }

  @Test("preview session ownership crosses actors with a Sendable AVFoundation type")
  func previewSessionIsSendable() {
    Self.requireSendable(AVCaptureSession.self)
  }

  #if !os(iOS)
    @Test("non-iOS camera adapter fails closed without hardware")
    func nonIOSAdapter() async {
      let session = AVFoundationIdentifyCameraSession()

      await #expect(throws: (any Error).self) { try await session.start() }
      await session.stop()
      _ = await AVFoundationCameraAuthorization().status()
    }

    @MainActor
    @Test("non-UIKit preview remains an inert view")
    func nonUIKitPreview() {
      _ = IdentifyCameraView(session: AVCaptureSession()).body
    }
  #endif

  @Test("sampling admits at most two frames per second")
  func samplingRate() {
    var gate = FrameSamplingGate(minimumIntervalNanoseconds: 500_000_000)

    let decisions = [
      gate.shouldAccept(timestampNanoseconds: 0),
      gate.shouldAccept(timestampNanoseconds: 499_999_999),
      gate.shouldAccept(timestampNanoseconds: 500_000_000),
      gate.shouldAccept(timestampNanoseconds: 999_999_999),
      gate.shouldAccept(timestampNanoseconds: 1_000_000_000),
    ]
    #expect(decisions == [true, false, true, false, true])
  }

  @Test("sampling accepts the first frame after a timestamp epoch rewinds")
  func samplingTimestampRewind() {
    var gate = FrameSamplingGate(minimumIntervalNanoseconds: 500_000_000)

    let decisions = [
      gate.shouldAccept(timestampNanoseconds: 8_000_000_000),
      gate.shouldAccept(timestampNanoseconds: 8_100_000_000),
      gate.shouldAccept(timestampNanoseconds: 100_000_000),
      gate.shouldAccept(timestampNanoseconds: 200_000_000),
      gate.shouldAccept(timestampNanoseconds: 600_000_000),
    ]

    #expect(decisions == [true, false, true, false, true])
  }

  @Test("zero-buffer stream drops frames without demand or while one is in flight")
  func boundedBackpressure() async throws {
    let channel = CameraFrameChannel.make()
    let frame = try Self.frame()

    guard case .dropped = channel.continuation.yield(frame) else {
      Issue.record("Expected a frame with no consumer to be dropped")
      return
    }

    let consumer = Task { await channel.frames.first { _ in true } }
    var delivered = false
    for _ in 0..<100 where !delivered {
      if case .enqueued = channel.continuation.yield(frame) { delivered = true }
      if !delivered { await Task.yield() }
    }
    guard delivered else {
      Issue.record("Expected a waiting consumer to receive one frame")
      return
    }
    let inFlight = await consumer.value
    #expect(inFlight != nil)
    guard case .dropped = channel.continuation.yield(frame) else {
      Issue.record("Expected a second frame to drop while no consumer is waiting")
      return
    }
    channel.continuation.finish()
  }

  @MainActor
  @Test(
    "denied, restricted, and unavailable permissions never start capture",
    arguments: [
      IdentifyCameraPermission.denied,
      .restricted,
      .unavailable,
    ])
  func unavailablePermission(permission: IdentifyCameraPermission) async {
    let authorization = RecordingCameraAuthorization(status: permission)
    let session = RecordingCameraSession()
    let coordinator = IdentifyCameraCoordinator(
      authorization: authorization,
      session: session
    )

    await coordinator.open()

    #expect(coordinator.state == .permission(permission))
    #expect(await session.startCount == 0)
    #expect(!coordinator.isPresented)
    if case .unavailable = coordinator.cameraState {
      // Expected safe user-facing mapping for every terminal permission state.
    } else {
      Issue.record("Expected unavailable camera presentation")
    }
  }

  @MainActor
  @Test("not-determined permission requests once and starts only when granted")
  func permissionRequest() async {
    let authorization = RecordingCameraAuthorization(status: .notDetermined, requestGranted: true)
    let session = RecordingCameraSession()
    let coordinator = IdentifyCameraCoordinator(
      authorization: authorization,
      session: session
    )

    await coordinator.open()

    #expect(await authorization.requestCount == 1)
    #expect(await session.startCount == 1)
    #expect(coordinator.state == .running)
    #expect(coordinator.isPresented)
  }

  @MainActor
  @Test("a denied permission request remains closed")
  func deniedPermissionRequest() async {
    let authorization = RecordingCameraAuthorization(status: .notDetermined)
    let session = RecordingCameraSession()
    let coordinator = IdentifyCameraCoordinator(
      authorization: authorization,
      session: session
    )

    await coordinator.open()

    #expect(await authorization.requestCount == 1)
    #expect(await session.startCount == 0)
    #expect(coordinator.state == .permission(.denied))
    #expect(!coordinator.isPresented)
  }

  @MainActor
  @Test("capture startup failure is presented as camera unavailable")
  func startupFailure() async {
    let authorization = RecordingCameraAuthorization(status: .authorized)
    let session = RecordingCameraSession(startError: CameraTestError.startup)
    let coordinator = IdentifyCameraCoordinator(
      authorization: authorization,
      session: session
    )

    await coordinator.open()

    #expect(await session.startCount == 1)
    #expect(await session.stopCount == 0)
    #expect(coordinator.state == .permission(.unavailable))
    #expect(!coordinator.isPresented)
  }

  @MainActor
  @Test("all lifecycle stops release capture exactly once per active run")
  func lifecycleReleaseCounts() async {
    let authorization = RecordingCameraAuthorization(status: .authorized)
    let session = RecordingCameraSession()
    let coordinator = IdentifyCameraCoordinator(
      authorization: authorization,
      session: session
    )

    await coordinator.open()
    await coordinator.applicationDidEnterBackground()
    await coordinator.applicationDidEnterBackground()
    await coordinator.open()
    await coordinator.viewDidDisappear()
    await coordinator.open()
    await coordinator.thermalStateDidChange(isSeriousOrCritical: false)
    await coordinator.thermalStateDidChange(isSeriousOrCritical: true)
    await coordinator.open()
    await coordinator.sessionWasInterrupted()
    await coordinator.open()
    await coordinator.close()

    #expect(await session.startCount == 5)
    #expect(await session.stopCount == 5)
    #expect(coordinator.state == .stopped(.explicitClose))
    #expect(!coordinator.isPresented)
  }

  @MainActor
  @Test(
    "every stop intent wins while authorization is suspended",
    arguments: PendingCameraStop.allCases)
  func stopDuringAuthorization(stop: PendingCameraStop) async {
    let authorization = SuspendedStatusCameraAuthorization()
    let session = ImmediateFinishCameraSession()
    let coordinator = IdentifyCameraCoordinator(
      authorization: authorization,
      session: session
    )
    let task = Task {
      if stop == .cancelled {
        await coordinator.run()
      } else {
        await coordinator.open()
      }
    }
    await authorization.waitUntilStatusRequested()

    if stop == .permissionLost {
      await authorization.setCurrentStatus(.denied)
    }
    await Self.request(stop: stop, coordinator: coordinator, task: task)
    await authorization.resumeInitialStatus(.authorized)
    await task.value

    #expect(await session.startCount == 0)
    #expect(await session.stopCount == 0)
    #expect(!coordinator.isPresented)
    #expect(coordinator.state != .running)
  }

  @MainActor
  @Test(
    "every stop intent releases a session whose start is suspended exactly once",
    arguments: PendingCameraStop.allCases)
  func stopDuringSessionStart(stop: PendingCameraStop) async {
    let authorization = RecordingCameraAuthorization(status: .authorized)
    let session = SuspendedStartCameraSession()
    let coordinator = IdentifyCameraCoordinator(
      authorization: authorization,
      session: session
    )
    let task = Task {
      if stop == .cancelled {
        await coordinator.run()
      } else {
        await coordinator.open()
      }
    }
    await session.waitUntilStartRequested()

    if stop == .permissionLost {
      await authorization.setStatus(.denied)
    }
    await Self.request(stop: stop, coordinator: coordinator, task: task)
    await session.resumeStart()
    await task.value

    #expect(await session.startCount == 1)
    #expect(await session.stopCount == 1)
    #expect(!coordinator.isPresented)
    #expect(coordinator.state != .running)
  }

  @MainActor
  @Test("a stop intent is preserved when a suspended session start later fails")
  func stopDuringFailingSessionStart() async {
    let authorization = RecordingCameraAuthorization(status: .authorized)
    let session = SuspendedFailingStartCameraSession()
    let coordinator = IdentifyCameraCoordinator(
      authorization: authorization,
      session: session
    )
    let task = Task { await coordinator.open() }
    await session.waitUntilStartRequested()

    await coordinator.close()
    await session.resumeStartWithFailure()
    await task.value

    #expect(await session.startCount == 1)
    #expect(await session.stopCount == 0)
    #expect(!coordinator.isPresented)
    #expect(coordinator.state == .stopped(.explicitClose))
  }

  @MainActor
  @Test("cancellation cleans up when a suspended session start later fails")
  func cancellationDuringFailingSessionStart() async {
    let authorization = RecordingCameraAuthorization(status: .authorized)
    let session = SuspendedFailingStartCameraSession()
    let coordinator = IdentifyCameraCoordinator(
      authorization: authorization,
      session: session
    )
    let task = Task { await coordinator.run() }
    await session.waitUntilStartRequested()

    task.cancel()
    await session.resumeStartWithFailure()
    await task.value

    #expect(await session.startCount == 1)
    #expect(await session.stopCount == 1)
    #expect(!coordinator.isPresented)
    #expect(coordinator.state == .stopped(.cancelled))
  }

  @MainActor
  @Test("permission loss stops and releases an active session")
  func permissionLoss() async {
    let authorization = RecordingCameraAuthorization(status: .authorized)
    let session = RecordingCameraSession()
    let coordinator = IdentifyCameraCoordinator(
      authorization: authorization,
      session: session
    )
    await coordinator.open()
    await authorization.setStatus(.denied)

    await coordinator.permissionDidChange()

    #expect(await session.stopCount == 1)
    #expect(coordinator.state == .permission(.denied))
    #expect(!coordinator.isPresented)
  }

  @MainActor
  @Test("cancelling a camera run releases its session once")
  func cancellation() async {
    let authorization = RecordingCameraAuthorization(status: .authorized)
    let session = RecordingCameraSession()
    let coordinator = IdentifyCameraCoordinator(
      authorization: authorization,
      session: session
    )
    let task = Task { await coordinator.run() }
    await session.waitUntilStarted()

    task.cancel()
    await task.value

    #expect(await session.stopCount == 1)
    #expect(coordinator.state == .stopped(.cancelled))
  }

  @MainActor
  @Test("capture interruption events release the active session")
  func interruptionEvent() async {
    let authorization = RecordingCameraAuthorization(status: .authorized)
    let session = RecordingCameraSession()
    let coordinator = IdentifyCameraCoordinator(
      authorization: authorization,
      session: session
    )
    let task = Task { await coordinator.run() }
    await session.waitUntilStarted()

    await session.emit(.interrupted)
    await task.value

    #expect(await session.stopCount == 1)
    #expect(coordinator.state == .stopped(.interrupted))
    #expect(!coordinator.isPresented)
  }

  @MainActor
  @Test("runtime failure events release capture and fail closed")
  func runtimeFailureEvent() async {
    let authorization = RecordingCameraAuthorization(status: .authorized)
    let session = RecordingCameraSession()
    let coordinator = IdentifyCameraCoordinator(
      authorization: authorization,
      session: session
    )
    let task = Task { await coordinator.run() }
    await session.waitUntilStarted()

    await session.emit(.failed)
    await task.value

    #expect(await session.stopCount == 1)
    #expect(coordinator.state == .permission(.unavailable))
    #expect(!coordinator.isPresented)
  }

  @MainActor
  @Test("media entry opens live capture and exposes the zero-buffer frame stream")
  func liveMediaEntry() async {
    let authorization = RecordingCameraAuthorization(status: .authorized)
    let session = RecordingCameraSession()
    let coordinator = IdentifyCameraCoordinator(
      authorization: authorization,
      session: session
    )

    await coordinator.openCamera()
    _ = coordinator.frames

    #expect(coordinator.previewSession == nil)
    #expect(coordinator.cameraState == .available)
    #expect(await session.startCount == 1)
    await coordinator.permissionDidChange()
    #expect(await session.stopCount == 0)
    await coordinator.close()
  }

  #if !os(iOS)
    @MainActor
    @Test("default non-iOS coordinator reports unavailable")
    func defaultCoordinator() async {
      let coordinator = IdentifyCameraCoordinator()

      await coordinator.open()

      #expect(coordinator.state == .permission(.unavailable))
      #expect(!coordinator.isPresented)
    }
  #endif
}

extension IdentifyCameraPipelineTests {
  @MainActor
  static func request(
    stop: PendingCameraStop,
    coordinator: IdentifyCameraCoordinator,
    task: Task<Void, Never>
  ) async {
    switch stop {
    case .close:
      await coordinator.close()
    case .background:
      await coordinator.applicationDidEnterBackground()
    case .viewDisappeared:
      await coordinator.viewDidDisappear()
    case .thermal:
      await coordinator.thermalStateDidChange(isSeriousOrCritical: true)
    case .permissionLost:
      await coordinator.permissionDidChange()
    case .interrupted:
      await coordinator.sessionWasInterrupted()
    case .cancelled:
      task.cancel()
    }
  }

  static func frame() throws -> CameraFrame {
    var pixelBuffer: CVPixelBuffer?
    guard
      CVPixelBufferCreate(
        kCFAllocatorDefault,
        1,
        1,
        kCVPixelFormatType_32BGRA,
        nil,
        &pixelBuffer
      ) == kCVReturnSuccess, let pixelBuffer
    else {
      throw CameraTestError.bufferCreation
    }
    return try CameraFrame(pixelBuffer: pixelBuffer, orientation: .up)
  }

  static func requireSendable<Value: Sendable>(_: Value.Type) {}
}

enum PendingCameraStop: CaseIterable, Sendable {
  case close
  case background
  case viewDisappeared
  case thermal
  case permissionLost
  case interrupted
  case cancelled
}

private enum CameraTestError: Error {
  case bufferCreation
  case startup
}

private actor RecordingCameraAuthorization: IdentifyCameraAuthorizationProviding {
  private var currentStatus: IdentifyCameraPermission
  private let requestGranted: Bool
  private(set) var requestCount = 0

  init(status: IdentifyCameraPermission, requestGranted: Bool = false) {
    currentStatus = status
    self.requestGranted = requestGranted
  }

  func status() -> IdentifyCameraPermission { currentStatus }

  func requestAccess() async -> Bool {
    requestCount += 1
    currentStatus = requestGranted ? .authorized : .denied
    return requestGranted
  }

  func setStatus(_ status: IdentifyCameraPermission) {
    currentStatus = status
  }
}

private actor RecordingCameraSession: IdentifyCameraSessionProviding {
  nonisolated let frames = CameraFrameChannel.make().frames
  nonisolated let events: AsyncStream<IdentifyCameraSessionEvent>
  nonisolated let previewSession: AVCaptureSession? = nil

  private let eventContinuation: AsyncStream<IdentifyCameraSessionEvent>.Continuation
  private let startError: (any Error)?
  private var startWaiters: [CheckedContinuation<Void, Never>] = []
  private(set) var startCount = 0
  private(set) var stopCount = 0

  init(startError: (any Error)? = nil) {
    let channel = AsyncStream<IdentifyCameraSessionEvent>.makeStream()
    events = channel.stream
    eventContinuation = channel.continuation
    self.startError = startError
  }

  func start() async throws {
    startCount += 1
    let waiters = startWaiters
    startWaiters = []
    waiters.forEach { $0.resume() }
    if let startError { throw startError }
  }

  func stop() {
    stopCount += 1
  }

  func emit(_ event: IdentifyCameraSessionEvent) {
    eventContinuation.yield(event)
  }

  func waitUntilStarted() async {
    guard startCount == 0 else { return }
    await withCheckedContinuation { startWaiters.append($0) }
  }
}

private actor SuspendedStatusCameraAuthorization: IdentifyCameraAuthorizationProviding {
  private var initialStatusContinuation: CheckedContinuation<IdentifyCameraPermission, Never>?
  private var requestWaiters: [CheckedContinuation<Void, Never>] = []
  private var currentStatus = IdentifyCameraPermission.authorized
  private var statusRequestCount = 0

  func status() async -> IdentifyCameraPermission {
    statusRequestCount += 1
    guard statusRequestCount == 1 else { return currentStatus }
    let waiters = requestWaiters
    requestWaiters = []
    waiters.forEach { $0.resume() }
    return await withCheckedContinuation { initialStatusContinuation = $0 }
  }

  func requestAccess() async -> Bool { currentStatus == .authorized }

  func waitUntilStatusRequested() async {
    guard statusRequestCount == 0 else { return }
    await withCheckedContinuation { requestWaiters.append($0) }
  }

  func setCurrentStatus(_ status: IdentifyCameraPermission) {
    currentStatus = status
  }

  func resumeInitialStatus(_ status: IdentifyCameraPermission) {
    initialStatusContinuation?.resume(returning: status)
    initialStatusContinuation = nil
  }
}

private actor ImmediateFinishCameraSession: IdentifyCameraSessionProviding {
  nonisolated let frames = CameraFrameChannel.make().frames
  nonisolated let events = AsyncStream<IdentifyCameraSessionEvent> { $0.finish() }
  nonisolated let previewSession: AVCaptureSession? = nil
  private(set) var startCount = 0
  private(set) var stopCount = 0

  func start() { startCount += 1 }
  func stop() { stopCount += 1 }
}

private actor SuspendedStartCameraSession: IdentifyCameraSessionProviding {
  nonisolated let frames = CameraFrameChannel.make().frames
  nonisolated let events = AsyncStream<IdentifyCameraSessionEvent> { $0.finish() }
  nonisolated let previewSession: AVCaptureSession? = nil
  private var startContinuation: CheckedContinuation<Void, Never>?
  private var startWaiters: [CheckedContinuation<Void, Never>] = []
  private(set) var startCount = 0
  private(set) var stopCount = 0

  func start() async {
    startCount += 1
    let waiters = startWaiters
    startWaiters = []
    waiters.forEach { $0.resume() }
    await withCheckedContinuation { startContinuation = $0 }
  }

  func stop() { stopCount += 1 }

  func waitUntilStartRequested() async {
    guard startCount == 0 else { return }
    await withCheckedContinuation { startWaiters.append($0) }
  }

  func resumeStart() {
    startContinuation?.resume()
    startContinuation = nil
  }
}

private actor SuspendedFailingStartCameraSession: IdentifyCameraSessionProviding {
  private enum StartFailure: Error { case rejected }

  nonisolated let frames = CameraFrameChannel.make().frames
  nonisolated let events = AsyncStream<IdentifyCameraSessionEvent> { $0.finish() }
  nonisolated let previewSession: AVCaptureSession? = nil
  private var startContinuation: CheckedContinuation<Void, any Error>?
  private var startWaiters: [CheckedContinuation<Void, Never>] = []
  private(set) var startCount = 0
  private(set) var stopCount = 0

  func start() async throws {
    startCount += 1
    let waiters = startWaiters
    startWaiters = []
    waiters.forEach { $0.resume() }
    try await withCheckedThrowingContinuation { startContinuation = $0 }
  }

  func stop() { stopCount += 1 }

  func waitUntilStartRequested() async {
    guard startCount == 0 else { return }
    await withCheckedContinuation { startWaiters.append($0) }
  }

  func resumeStartWithFailure() {
    startContinuation?.resume(throwing: StartFailure.rejected)
    startContinuation = nil
  }
}
