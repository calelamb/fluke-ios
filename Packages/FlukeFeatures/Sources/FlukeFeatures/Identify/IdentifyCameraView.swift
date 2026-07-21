import AVFoundation
import SwiftUI

#if canImport(UIKit)
  import UIKit

  public struct IdentifyCameraView: UIViewRepresentable {
    private let session: AVCaptureSession

    public init(session: AVCaptureSession) {
      self.session = session
    }

    public func makeUIView(context: Context) -> IdentifyCameraPreviewView {
      let view = IdentifyCameraPreviewView()
      view.update(session: session)
      return view
    }

    public func updateUIView(_ view: IdentifyCameraPreviewView, context: Context) {
      view.update(session: session)
    }
  }

  @MainActor
  public final class IdentifyCameraPreviewView: UIView {
    public override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    private var previewLayer: AVCaptureVideoPreviewLayer {
      layer as! AVCaptureVideoPreviewLayer
    }

    public override init(frame: CGRect) {
      super.init(frame: frame)
      previewLayer.videoGravity = .resizeAspectFill
      accessibilityLabel = "Live dorsal fin camera preview"
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { nil }

    func update(session: AVCaptureSession) {
      guard previewLayer.session !== session else { return }
      previewLayer.session = session
    }
  }
#else
  public struct IdentifyCameraView: View {
    public init(session: AVCaptureSession) {}
    public var body: some View { EmptyView() }
  }
#endif
