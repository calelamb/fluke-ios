import FlukeML
import Foundation
import Observation

public enum IdentifyUnavailableReason: Equatable, Sendable {
  case localArtifactsUnavailable
  case serverUnsupported
}

public enum IdentifyCapability: Sendable {
  case disabled
  case onDevice(any LocalIdentifying)
  case unavailable(IdentifyUnavailableReason)
}

extension IdentifyCapability {
  public var unavailableReason: IdentifyUnavailableReason? {
    guard case .unavailable(let reason) = self else { return nil }
    return reason
  }
}

public enum IdentifyAvailability: Equatable, Sendable {
  case disabled
  case unavailable(IdentifyUnavailableReason)
  case ready
}

public enum IdentifyPresentation: Equatable, Sendable {
  case idle
  case analyzing
  case provisional
  case stabilized
  case unknown
  case poorQuality
  case unavailable
}

public struct IdentifyResultMatch: Equatable, Sendable, Identifiable {
  public var id: String { whaleID }
  public let whaleID: String
  public let catalogID: String
  public let score: Float
  public let rank: Int
  public let referencePhotoIDs: [String]
}

public struct IdentifyResult: Equatable, Sendable {
  public let provisional: [IdentifyResultMatch]
  public let prominent: IdentifyResultMatch?
  public let artifact: LocalIdentificationArtifact
}

@MainActor
public protocol IdentifyMediaProviding: AnyObject {
  var cameraState: PhotoCameraState { get }
  var frames: AsyncStream<CameraFrame> { get }
  var isCameraPresented: Bool { get }
  func openCamera() async
}

@MainActor
@Observable
public final class IdentifyViewModel {
  public private(set) var availability: IdentifyAvailability
  public private(set) var presentation = IdentifyPresentation.idle
  public private(set) var result: IdentifyResult?
  public private(set) var isIdentifying = false

  public let disclaimer = "Uncalibrated visual similarity, not a confirmed ID"

  private let capability: IdentifyCapability
  private let media: any IdentifyMediaProviding
  private var inferenceTask: Task<Void, Never>?

  public init(capability: IdentifyCapability, media: any IdentifyMediaProviding) {
    self.capability = capability
    self.media = media
    availability =
      switch capability {
      case .disabled: .disabled
      case .unavailable(let reason): .unavailable(reason)
      case .onDevice: .ready
      }
  }

  public var cameraState: PhotoCameraState { media.cameraState }

  public var unavailableMessage: String? {
    switch availability {
    case .disabled:
      "On-device identification is not enabled for this release."
    case .unavailable(.localArtifactsUnavailable):
      "On-device identification is unavailable because its verified model catalog could not load."
    case .unavailable(.serverUnsupported):
      "Server identification is not supported in this app."
    case .ready:
      nil
    }
  }

  public func openCamera() async {
    guard case .onDevice(let identifier) = capability, !media.isCameraPresented else { return }
    guard case .available = media.cameraState else { return }
    result = nil
    presentation = .analyzing
    await media.openCamera()
    guard media.isCameraPresented else {
      presentation = .idle
      return
    }
    consumeFrames(using: identifier)
  }

  public func cameraDidStop() {
    inferenceTask?.cancel()
    inferenceTask = nil
    isIdentifying = false
    if result == nil { presentation = .idle }
  }

  private func consumeFrames(using identifier: any LocalIdentifying) {
    inferenceTask?.cancel()
    let frames = media.frames
    inferenceTask = Task { [weak self] in
      for await frame in frames {
        guard !Task.isCancelled else { break }
        self?.isIdentifying = true
        do {
          let state = try await identifier.identify(frame: frame)
          guard !Task.isCancelled else { break }
          self?.apply(state)
        } catch is CancellationError {
          break
        } catch {
          guard !Task.isCancelled else { break }
          self?.apply(error)
        }
        self?.isIdentifying = false
      }
      self?.isIdentifying = false
    }
  }

  private func apply(_ state: LocalIdentificationState) {
    let provisional = state.matches.map(Self.presentationMatch)
    let prominent = state.prominent.map(Self.presentationMatch)
    result = IdentifyResult(
      provisional: provisional,
      prominent: prominent,
      artifact: state.artifact
    )
    if prominent != nil {
      presentation = .stabilized
    } else if provisional.isEmpty {
      presentation = .unknown
    } else {
      presentation = .provisional
    }
  }

  private func apply(_ error: any Error) {
    result = nil
    switch error {
    case LocalIdentifierError.invalidPixelBuffer, LocalIdentifierError.preprocessingFailed:
      presentation = .poorQuality
    default:
      presentation = .unavailable
    }
  }

  private static func presentationMatch(_ match: LocalMatch) -> IdentifyResultMatch {
    IdentifyResultMatch(
      whaleID: match.whaleID,
      catalogID: match.catalogID,
      score: match.score,
      rank: match.rank,
      referencePhotoIDs: match.matchedReferencePhotoIDs
    )
  }
}
