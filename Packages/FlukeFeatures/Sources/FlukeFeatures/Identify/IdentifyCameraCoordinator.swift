import AVFoundation
import FlukeML
import Foundation
import Observation

@MainActor
@Observable
final class IdentifyCameraCoordinator: IdentifyMediaProviding {
  private(set) var state = IdentifyCameraPresentationState.closed
  private(set) var isPresented = false

  var frames: AsyncStream<CameraFrame> {
    session?.frames ?? AsyncStream { $0.finish() }
  }
  var previewSession: AVCaptureSession? { session?.previewSession }
  var isCameraPresented: Bool { isPresented }

  private let authorization: any IdentifyCameraAuthorizationProviding
  private let makeSession: () -> any IdentifyCameraSessionProviding
  private var session: (any IdentifyCameraSessionProviding)?
  private var openingGeneration: UInt64?
  private var openingWaiters: [CheckedContinuation<Void, Never>] = []
  private var isSessionActive = false
  private var lifecycleGeneration: UInt64 = 0

  convenience init() {
    self.init(
      authorization: AVFoundationCameraAuthorization(),
      session: nil,
      makeSession: { AVFoundationIdentifyCameraSession() }
    )
  }

  convenience init(
    authorization: any IdentifyCameraAuthorizationProviding,
    session: any IdentifyCameraSessionProviding
  ) {
    self.init(authorization: authorization, session: session, makeSession: { session })
  }

  private init(
    authorization: any IdentifyCameraAuthorizationProviding,
    session: (any IdentifyCameraSessionProviding)?,
    makeSession: @escaping () -> any IdentifyCameraSessionProviding
  ) {
    self.authorization = authorization
    self.session = session
    self.makeSession = makeSession
  }

  var cameraState: PhotoCameraState {
    switch state {
    case .permission(.denied):
      PhotoSelectionPresentation.cameraState(for: .denied)
    case .permission(.restricted):
      PhotoSelectionPresentation.cameraState(for: .restricted)
    case .permission(.unavailable):
      PhotoSelectionPresentation.cameraState(for: .unavailable)
    default:
      .available
    }
  }

  func openCamera() async { await open() }

  func open() async {
    let requestedGeneration = lifecycleGeneration
    if let activeOpeningGeneration = openingGeneration {
      await waitForOpening()
      guard requestedGeneration == lifecycleGeneration else { return }
      if activeOpeningGeneration != requestedGeneration { await open() }
      return
    }
    guard !isSessionActive else { return }
    openingGeneration = requestedGeneration
    await performOpen(generation: requestedGeneration)
    finishOpening(generation: requestedGeneration)
  }

  private func performOpen(generation openingGeneration: UInt64) async {
    state = .requestingPermission
    let permission = await resolvedPermission()
    guard await openingMayContinue(generation: openingGeneration) else { return }
    guard permission == .authorized else {
      state = .permission(permission)
      isPresented = false
      return
    }
    let session = resolvedSession()
    do {
      try await session.start()
      isSessionActive = true
      guard await startedSessionMayPublish(generation: openingGeneration, session: session) else {
        return
      }
      isPresented = true
      state = .running
    } catch {
      guard openingGeneration == lifecycleGeneration else { return }
      if Task.isCancelled {
        await stopAfterCancelledStart(session: session)
        return
      }
      isPresented = false
      state = .permission(.unavailable)
    }
  }

  func run() async {
    let runGeneration = lifecycleGeneration
    await open()
    guard runGeneration == lifecycleGeneration else { return }
    guard isSessionActive, let session else { return }
    for await event in session.events {
      if Task.isCancelled || runGeneration != lifecycleGeneration { break }
      switch event {
      case .interrupted:
        await stop(for: .interrupted)
      case .failed:
        await stopForUnavailableSession()
      }
      break
    }
    if Task.isCancelled, runGeneration == lifecycleGeneration {
      await stop(for: .cancelled)
    }
  }

  func applicationDidEnterBackground() async {
    await stop(for: .backgrounded)
  }

  func viewDidDisappear() async {
    await stop(for: .viewDisappeared)
  }

  func thermalStateDidChange(isSeriousOrCritical: Bool) async {
    guard isSeriousOrCritical else { return }
    await stop(for: .thermalPressure)
  }

  func sessionWasInterrupted() async {
    await stop(for: .interrupted)
  }

  func permissionDidChange() async {
    let permission = await authorization.status()
    guard permission != .authorized else { return }
    await stop(for: .permissionLost)
    state = .permission(permission == .notDetermined ? .unavailable : permission)
  }

  func close() async {
    await stop(for: .explicitClose)
  }

  private func resolvedPermission() async -> IdentifyCameraPermission {
    let permission = await authorization.status()
    guard permission == .notDetermined else { return permission }
    _ = await authorization.requestAccess()
    return await authorization.status()
  }

  private func stop(for reason: IdentifyCameraStopReason) async {
    lifecycleGeneration &+= 1
    isPresented = false
    state = .stopped(reason)
    guard isSessionActive, let session else { return }
    isSessionActive = false
    await session.stop()
  }

  private func stopForUnavailableSession() async {
    lifecycleGeneration &+= 1
    guard isSessionActive, let session else { return }
    isSessionActive = false
    isPresented = false
    await session.stop()
    state = .permission(.unavailable)
  }

  private func stopAfterCancelledStart(
    session: any IdentifyCameraSessionProviding
  ) async {
    lifecycleGeneration &+= 1
    isSessionActive = false
    isPresented = false
    state = .stopped(.cancelled)
    await session.stop()
  }

  private func openingMayContinue(generation: UInt64) async -> Bool {
    guard !Task.isCancelled else {
      await stop(for: .cancelled)
      return false
    }
    return generation == lifecycleGeneration
  }

  private func startedSessionMayPublish(
    generation: UInt64,
    session: any IdentifyCameraSessionProviding
  ) async -> Bool {
    guard !Task.isCancelled else {
      await stop(for: .cancelled)
      return false
    }
    guard generation == lifecycleGeneration else {
      isSessionActive = false
      await session.stop()
      return false
    }
    return true
  }

  private func resolvedSession() -> any IdentifyCameraSessionProviding {
    if let session { return session }
    let session = makeSession()
    self.session = session
    return session
  }

  private func waitForOpening() async {
    guard openingGeneration != nil else { return }
    await withCheckedContinuation { openingWaiters.append($0) }
  }

  private func finishOpening(generation: UInt64) {
    guard openingGeneration == generation else { return }
    openingGeneration = nil
    let waiters = openingWaiters
    openingWaiters = []
    for waiter in waiters { waiter.resume() }
  }
}
