import Observation

@MainActor
@Observable
final class IdentifyReadyState {
  let camera: IdentifyCameraCoordinator
  let model: IdentifyViewModel

  convenience init(capability: IdentifyCapability) {
    self.init(capability: capability, camera: IdentifyCameraCoordinator())
  }

  init(capability: IdentifyCapability, camera: IdentifyCameraCoordinator) {
    self.camera = camera
    model = IdentifyViewModel(capability: capability, media: camera)
  }
}
