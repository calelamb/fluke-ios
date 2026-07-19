import AVFoundation
import FlukeML
import Foundation

public enum IdentifyCameraPermission: Equatable, Sendable {
  case notDetermined
  case authorized
  case denied
  case restricted
  case unavailable
}

public enum IdentifyCameraStopReason: Equatable, Sendable {
  case viewDisappeared
  case backgrounded
  case permissionLost
  case thermalPressure
  case interrupted
  case explicitClose
  case cancelled
}

public enum IdentifyCameraPresentationState: Equatable, Sendable {
  case closed
  case requestingPermission
  case running
  case permission(IdentifyCameraPermission)
  case stopped(IdentifyCameraStopReason)
}

enum IdentifyCameraSessionEvent: Sendable {
  case interrupted
  case failed
}

protocol IdentifyCameraAuthorizationProviding: Sendable {
  func status() async -> IdentifyCameraPermission
  func requestAccess() async -> Bool
}

protocol IdentifyCameraSessionProviding: Sendable {
  var frames: AsyncStream<CameraFrame> { get }
  var events: AsyncStream<IdentifyCameraSessionEvent> { get }
  var previewSession: AVCaptureSession? { get }

  func start() async throws
  func stop() async
}

struct CameraFrameChannel: Sendable {
  let frames: AsyncStream<CameraFrame>
  let continuation: AsyncStream<CameraFrame>.Continuation

  static func make() -> CameraFrameChannel {
    let channel = AsyncStream<CameraFrame>.makeStream(bufferingPolicy: .bufferingNewest(0))
    return CameraFrameChannel(frames: channel.stream, continuation: channel.continuation)
  }
}

struct FrameSamplingGate: Sendable {
  let minimumIntervalNanoseconds: UInt64
  private var lastAcceptedNanoseconds: UInt64?

  init(minimumIntervalNanoseconds: UInt64 = 500_000_000) {
    precondition(minimumIntervalNanoseconds > 0)
    self.minimumIntervalNanoseconds = minimumIntervalNanoseconds
  }

  mutating func shouldAccept(timestampNanoseconds: UInt64) -> Bool {
    guard let lastAcceptedNanoseconds else {
      self.lastAcceptedNanoseconds = timestampNanoseconds
      return true
    }
    guard timestampNanoseconds >= lastAcceptedNanoseconds else {
      self.lastAcceptedNanoseconds = timestampNanoseconds
      return true
    }
    guard timestampNanoseconds - lastAcceptedNanoseconds >= minimumIntervalNanoseconds
    else {
      return false
    }
    self.lastAcceptedNanoseconds = timestampNanoseconds
    return true
  }
}
