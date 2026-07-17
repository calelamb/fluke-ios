import FlukeReleaseB
import PhotosUI
import SwiftUI
#if canImport(UIKit)
import AVFoundation
import UIKit
#endif

public struct PhotoPicker: View {
  @State private var selections: [PhotosPickerItem] = []
  #if canImport(UIKit)
  @State private var showsCamera = false
  #endif
  let addPhotos: ([ProcessedPhoto]) -> Void
  let reportFailure: (PhotoSelectionFailure) -> Void

  public init(
    addPhotos: @escaping ([ProcessedPhoto]) -> Void,
    reportFailure: @escaping (PhotoSelectionFailure) -> Void
  ) {
    self.addPhotos = addPhotos
    self.reportFailure = reportFailure
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      PhotosPicker(selection: $selections, maxSelectionCount: 5, matching: .images) {
        Label("Choose photos", systemImage: "photo.on.rectangle")
      }
      #if canImport(UIKit)
      switch cameraState {
      case .available:
        Button("Take photo", systemImage: "camera") { showsCamera = true }
      case .unavailable(let message):
        Text(message).font(.footnote).foregroundStyle(.secondary)
      }
      #endif
    }
    .onChange(of: selections) { _, values in
      Task {
        await process(values)
      }
    }
    #if canImport(UIKit)
    .sheet(isPresented: $showsCamera) {
      CameraPicker { data in
        do {
          addPhotos([try ImageProcessor.process(data)])
        } catch {
          reportFailure(.processingFailed)
        }
      }
    }
    #endif
  }

  private func process(_ values: [PhotosPickerItem]) async {
    var processed: [ProcessedPhoto] = []
    for item in values {
      let data: Data
      do {
        guard let loaded = try await item.loadTransferable(type: Data.self) else {
          await MainActor.run { reportFailure(.loadFailed) }
          continue
        }
        data = loaded
      } catch {
        await MainActor.run { reportFailure(.loadFailed) }
        continue
      }
      do {
        processed.append(try ImageProcessor.process(data))
      } catch {
        await MainActor.run { reportFailure(.processingFailed) }
      }
    }
    if !processed.isEmpty { await MainActor.run { addPhotos(processed) } }
  }

  #if canImport(UIKit)
  private var cameraState: PhotoCameraState {
    guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
      return PhotoSelectionPresentation.cameraState(for: .unavailable)
    }
    let authorization: PhotoCameraAuthorization = switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .denied: .denied
    case .restricted: .restricted
    default: .available
    }
    return PhotoSelectionPresentation.cameraState(for: authorization)
  }
  #endif
}

#if canImport(UIKit)
private struct CameraPicker: UIViewControllerRepresentable {
  let completion: (Data) -> Void
  func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
  func makeUIViewController(context: Context) -> UIImagePickerController {
    let controller = UIImagePickerController()
    controller.sourceType = .camera
    controller.delegate = context.coordinator
    return controller
  }
  func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

  final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
    let completion: (Data) -> Void
    init(completion: @escaping (Data) -> Void) { self.completion = completion }
    func imagePickerController(
      _ picker: UIImagePickerController,
      didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
      defer { picker.dismiss(animated: true) }
      guard let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.95) else { return }
      completion(data)
    }
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { picker.dismiss(animated: true) }
  }
}
#endif
