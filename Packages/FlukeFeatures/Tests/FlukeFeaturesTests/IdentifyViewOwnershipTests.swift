import AVFoundation
import FlukeML
import Testing

@testable import FlukeFeatures

@MainActor
@Suite("Identify view ownership")
struct IdentifyViewOwnershipTests {
  @Test("convenience owner keeps camera-only capability matching-inactive")
  func cameraOnlyConvenienceOwner() {
    let owner = IdentifyReadyState(capability: .cameraOnly(.notEnabledForRelease))

    #expect(owner.model.availability == .cameraOnly(.notEnabledForRelease))
    #expect(owner.model.submissionSuggestion == nil)
  }

  @Test("one retained owner wires the model and sheet to the same camera")
  func retainedCameraOwner() async {
    let authorization = OwnershipAuthorization()
    let session = OwnershipSession()
    let camera = IdentifyCameraCoordinator(authorization: authorization, session: session)
    let owner = IdentifyReadyState(
      capability: .onDevice(OwnershipLocalIdentifier()),
      camera: camera
    )

    await owner.model.openCamera()

    #expect(owner.camera === camera)
    #expect(owner.camera.isPresented)
    #expect(await session.startCount == 1)
  }
}

private struct OwnershipAuthorization: IdentifyCameraAuthorizationProviding {
  func status() async -> IdentifyCameraPermission { .authorized }
  func requestAccess() async -> Bool { true }
}

private actor OwnershipSession: IdentifyCameraSessionProviding {
  nonisolated let frames = CameraFrameChannel.make().frames
  nonisolated let events = AsyncStream<IdentifyCameraSessionEvent> { $0.finish() }
  nonisolated let previewSession: AVCaptureSession? = nil
  private(set) var startCount = 0

  func start() { startCount += 1 }
  func stop() {}
}

private struct OwnershipLocalIdentifier: LocalIdentifying {
  func identify(frame: CameraFrame) async throws -> LocalIdentificationState {
    throw CancellationError()
  }
}
