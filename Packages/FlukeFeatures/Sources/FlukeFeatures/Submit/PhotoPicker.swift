import FlukeReleaseB
import PhotosUI
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public struct PhotoPicker: View {
  @State private var selections: [PhotosPickerItem] = []
  #if canImport(UIKit)
  @State private var showsCamera = false
  #endif
  let addPhotos: ([ProcessedPhoto]) -> Void

  public init(addPhotos: @escaping ([ProcessedPhoto]) -> Void) { self.addPhotos = addPhotos }

  public var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      PhotosPicker(selection: $selections, maxSelectionCount: 5, matching: .images) {
        Label("Choose photos", systemImage: "photo.on.rectangle")
      }
      #if canImport(UIKit)
      Button("Take photo", systemImage: "camera") { showsCamera = true }
        .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
      #endif
    }
    .onChange(of: selections) { _, values in
      Task {
        let processed: [ProcessedPhoto] = await values.asyncCompactMap { item in
          guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
          return try? ImageProcessor.process(data)
        }
        await MainActor.run { addPhotos(processed) }
      }
    }
    #if canImport(UIKit)
    .sheet(isPresented: $showsCamera) {
      CameraPicker { data in
        guard let photo = try? ImageProcessor.process(data) else { return }
        addPhotos([photo])
      }
    }
    #endif
  }
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

private extension Array {
  func asyncCompactMap<T>(_ transform: (Element) async -> T?) async -> [T] {
    var result: [T] = []
    for element in self {
      if let value = await transform(element) { result.append(value) }
    }
    return result
  }
}
