import FlukeML
import FlukeReleaseB
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
  private var openingGeneration: UInt64?
  private var openingWaiters: [CheckedContinuation<Void, Never>] = []
  private var lifecycleGeneration: UInt64 = 0

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

  public var submissionSuggestion: LocalIdentificationSuggestion? {
    guard presentation == .stabilized, let result, let prominent = result.prominent else {
      return nil
    }
    return LocalIdentificationSuggestion(
      catalogID: prominent.catalogID,
      similarityScore: Double(prominent.score),
      scoreSemantics: result.artifact.scoreSemantics,
      manifestVersion: result.artifact.manifestVersion,
      modelVersion: result.artifact.modelVersion,
      indexVersion: result.artifact.indexVersion,
      matchedReferencePhotoIDs: prominent.referencePhotoIDs
    )
  }

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
    guard case .onDevice(let identifier) = capability else { return }
    let requestedGeneration = lifecycleGeneration
    if let activeOpeningGeneration = openingGeneration {
      await waitForOpening()
      guard requestedGeneration == lifecycleGeneration else { return }
      if activeOpeningGeneration != requestedGeneration { await openCamera() }
      return
    }
    guard !media.isCameraPresented else { return }
    guard case .available = media.cameraState else { return }
    openingGeneration = requestedGeneration
    await performOpen(identifier: identifier, generation: requestedGeneration)
    finishOpening(generation: requestedGeneration)
  }

  private func performOpen(
    identifier: any LocalIdentifying,
    generation: UInt64
  ) async {
    result = nil
    presentation = .analyzing
    await identifier.resetSession()
    await media.openCamera()
    guard generation == lifecycleGeneration else { return }
    guard media.isCameraPresented else {
      presentation = .idle
      return
    }
    consumeFrames(using: identifier, generation: generation)
  }

  public func cameraDidStop() {
    lifecycleGeneration &+= 1
    inferenceTask?.cancel()
    inferenceTask = nil
    isIdentifying = false
    if result == nil { presentation = .idle }
  }

  private func consumeFrames(
    using identifier: any LocalIdentifying,
    generation: UInt64
  ) {
    inferenceTask?.cancel()
    let frames = media.frames
    inferenceTask = Task { [weak self] in
      for await frame in frames {
        guard !Task.isCancelled, self?.lifecycleGeneration == generation else { break }
        self?.isIdentifying = true
        do {
          let state = try await identifier.identify(frame: frame)
          guard !Task.isCancelled, self?.lifecycleGeneration == generation else { break }
          self?.apply(state)
        } catch is CancellationError {
          break
        } catch {
          guard !Task.isCancelled, self?.lifecycleGeneration == generation else { break }
          self?.apply(error)
        }
        self?.finishInference(generation: generation)
      }
      self?.finishInference(generation: generation)
    }
  }

  private func finishInference(generation: UInt64) {
    guard generation == lifecycleGeneration else { return }
    isIdentifying = false
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
