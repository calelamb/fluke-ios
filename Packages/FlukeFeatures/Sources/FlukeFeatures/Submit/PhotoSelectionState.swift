import Foundation

public enum PhotoSelectionFailure: Equatable, Sendable {
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
}
