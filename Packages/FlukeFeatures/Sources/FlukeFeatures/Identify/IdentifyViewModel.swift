import FlukeKit
import FlukeReleaseB
import Foundation
import Observation

public enum IdentifyAvailability: Equatable, Sendable {
  case disabled
  case training
  case needsInternet
  case ready
}

@MainActor
public protocol IdentifyMediaProviding: AnyObject {
  func requestCameraPhoto() async throws -> IdentifyPhoto?
}

@MainActor
@Observable
public final class IdentifyViewModel {
  public static let trainingMessage =
    "Photo identification is still in training. We are building a rights-cleared reference catalog before we compare your photo. Browse the whale catalog or submit a sighting in the meantime."

  public private(set) var availability: IdentifyAvailability
  public private(set) var matches: [IdentifyMatch] = []
  public private(set) var errorMessage: String?
  public private(set) var isIdentifying = false

  public let disclaimer = "Visual similarity, not a confirmed ID"
  public let isWrongMatchFeedbackEnabled = false

  private let capability: Bool
  private let media: any IdentifyMediaProviding
  private let service: any IdentifyServiceProtocol

  public init(
    capability: Bool,
    online: Bool,
    media: any IdentifyMediaProviding,
    service: any IdentifyServiceProtocol
  ) {
    self.capability = capability
    self.media = media
    self.service = service
    availability = capability ? (online ? .ready : .needsInternet) : .training
  }

  public var unavailableMessage: String? {
    switch availability {
    case .disabled, .training: Self.trainingMessage
    case .needsInternet:
      "Photo identification needs an internet connection. Browse whales or try again when you are online."
    case .ready: nil
    }
  }

  public func openCamera() async {
    guard capability, availability != .needsInternet, !isIdentifying else { return }
    do {
      guard let photo = try await media.requestCameraPhoto() else { return }
      await identify(photo: photo)
    } catch is CancellationError {
      resetAfterCancellation()
    } catch {
      errorMessage = "Fluke could not open the camera. Please try a photo from your library."
    }
  }

  public func identify(photo: IdentifyPhoto) async {
    guard capability, availability != .needsInternet, !isIdentifying else { return }
    isIdentifying = true
    errorMessage = nil
    defer { isIdentifying = false }
    do {
      let response = try await service.identify(photo: photo)
      matches = response.matches
      availability = .ready
    } catch is CancellationError {
      resetAfterCancellation()
    } catch IdentifyServiceError.training {
      matches = []
      availability = .training
    } catch APIError.offline {
      matches = []
      availability = .needsInternet
    } catch {
      matches = []
      errorMessage = "Fluke could not compare this photo. Please try again."
    }
  }

  public func reportInvalidPhoto() {
    matches = []
    errorMessage = "Choose a valid JPEG photo with a clearly visible dorsal fin."
  }

  private func resetAfterCancellation() {
    matches = []
    errorMessage = nil
    availability = capability ? .ready : .training
  }
}
