import Foundation

public enum PhotoSelectionFailure: Error, Equatable, Sendable {
  case loadFailed
  case processingFailed
}

public enum PhotoCameraAuthorization: Equatable, Sendable {
  case available
  case denied
  case restricted
  case unavailable
}

public enum PhotoCameraState: Equatable, Sendable {
  case available
  case unavailable(String)
}

public enum PhotoSelectionPresentation {
  public static func message(for failure: PhotoSelectionFailure) -> String {
    switch failure {
    case .loadFailed:
      "Fluke couldn't read the selected photo. Choose another photo and try again."
    case .processingFailed:
      "That photo couldn't be prepared. Choose a JPEG or HEIC image under the size limit."
    }
  }

  public static func cameraState(for authorization: PhotoCameraAuthorization) -> PhotoCameraState {
    switch authorization {
    case .available:
      .available
    case .denied:
      .unavailable("Camera access is off. You can enable it in Settings or choose a photo instead.")
    case .restricted:
      .unavailable("Camera access is restricted on this device. Choose a photo instead.")
    case .unavailable:
      .unavailable("A camera isn't available on this device. Choose a photo instead.")
    }
  }

  public static func cameraResult(data: Data?) -> Result<Data, PhotoSelectionFailure> {
    guard let data else { return .failure(.processingFailed) }
    return .success(data)
  }
}

public struct PhotoSelectionTracker: Sendable {
  private var handledIdentifiers: Set<String> = []

  public init() {}

  private init(handledIdentifiers: Set<String>) {
    self.handledIdentifiers = handledIdentifiers
  }

  public func consuming(_ identifiers: [String?]) -> PhotoSelectionBatch {
    let result = identifiers.enumerated().reduce(
      (indices: [Int](), identifiers: handledIdentifiers)
    ) { partial, element in
      let (index, identifier) = element
      guard let identifier else {
        return (partial.indices + [index], partial.identifiers)
      }
      guard !partial.identifiers.contains(identifier) else { return partial }
      return (partial.indices + [index], partial.identifiers.union([identifier]))
    }
    return PhotoSelectionBatch(
      indices: result.indices,
      tracker: PhotoSelectionTracker(handledIdentifiers: result.identifiers)
    )
  }
}

public struct PhotoSelectionBatch: Sendable {
  public let indices: [Int]
  public let tracker: PhotoSelectionTracker
}
