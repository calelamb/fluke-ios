import AVFoundation
import FlukeML
import FlukeReleaseB
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

  private let authorization: any IdentifyCameraAuthorizationProviding
  private let makeSession: () -> any IdentifyCameraSessionProviding
  private var session: (any IdentifyCameraSessionProviding)?
  private var isSessionActive = false

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

  func requestCameraPhoto() async throws -> IdentifyPhoto? {
    await open()
    return nil
  }

  func open() async {
    guard !isSessionActive else { return }
    state = .requestingPermission
    let permission = await resolvedPermission()
    guard permission == .authorized else {
      state = .permission(permission)
      isPresented = false
      return
    }
    let session = resolvedSession()
    do {
      try await session.start()
      isSessionActive = true
      isPresented = true
      state = .running
    } catch {
      isPresented = false
      state = .permission(.unavailable)
    }
  }

  func run() async {
    await open()
    guard isSessionActive, let session else { return }
    for await event in session.events {
      if Task.isCancelled { break }
      switch event {
      case .interrupted:
        await stop(for: .interrupted)
      case .failed:
        await stopForUnavailableSession()
      }
      break
    }
    if Task.isCancelled { await stop(for: .cancelled) }
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
    guard isSessionActive, let session else { return }
    isSessionActive = false
    isPresented = false
    await session.stop()
    state = .stopped(reason)
  }

  private func stopForUnavailableSession() async {
    guard isSessionActive, let session else { return }
    isSessionActive = false
    isPresented = false
    await session.stop()
    state = .permission(.unavailable)
  }

  private func resolvedSession() -> any IdentifyCameraSessionProviding {
    if let session { return session }
    let session = makeSession()
    self.session = session
    return session
  }
}
