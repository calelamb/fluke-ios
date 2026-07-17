import FlukeReleaseB
import Foundation
import Observation
import SwiftUI

#if canImport(UIKit)
  import UIKit

  @MainActor
  @Observable
  final class IdentifyCameraCoordinator: IdentifyMediaProviding {
    var isPresented = false
    private var continuation: CheckedContinuation<IdentifyPhoto?, Error>?

    func requestCameraPhoto() async throws -> IdentifyPhoto? {
      guard continuation == nil, UIImagePickerController.isSourceTypeAvailable(.camera) else {
        return nil
      }
      return try await withCheckedThrowingContinuation { continuation in
        self.continuation = continuation
        isPresented = true
      }
    }

    func complete(with data: Data?) {
      defer { finishPresentation() }
      guard let data else {
        continuation?.resume(returning: nil)
        continuation = nil
        return
      }
      do {
        continuation?.resume(returning: try IdentifyPhoto(bytes: data))
      } catch {
        continuation?.resume(throwing: error)
      }
      continuation = nil
    }

    func cancel() {
      continuation?.resume(returning: nil)
      continuation = nil
      finishPresentation()
    }

    private func finishPresentation() { isPresented = false }
  }

  public struct IdentifyCameraView: UIViewControllerRepresentable {
    let onPhoto: (Data?) -> Void
    let onCancel: () -> Void

    public init(onPhoto: @escaping (Data?) -> Void, onCancel: @escaping () -> Void) {
      self.onPhoto = onPhoto
      self.onCancel = onCancel
    }

    public func makeUIViewController(context: Context) -> UIImagePickerController {
      let picker = UIImagePickerController()
      picker.sourceType = .camera
      picker.cameraCaptureMode = .photo
      picker.delegate = context.coordinator
      picker.accessibilityLabel = "Dorsal fin camera"
      return picker
    }

    public func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    public func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    public final class Coordinator: NSObject, UIImagePickerControllerDelegate,
      UINavigationControllerDelegate
    {
      private let parent: IdentifyCameraView
      init(parent: IdentifyCameraView) { self.parent = parent }

      public func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
      ) {
        let data = (info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 0.82)
        parent.onPhoto(data)
      }

      public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        parent.onCancel()
      }
    }
  }
#else
  @MainActor
  @Observable
  final class IdentifyCameraCoordinator: IdentifyMediaProviding {
    var isPresented = false
    func requestCameraPhoto() async throws -> IdentifyPhoto? { nil }
    func complete(with data: Data?) {}
    func cancel() {}
  }

  public struct IdentifyCameraView: View {
    public init(onPhoto: @escaping (Data?) -> Void, onCancel: @escaping () -> Void) {}
    public var body: some View { EmptyView() }
  }
#endif
