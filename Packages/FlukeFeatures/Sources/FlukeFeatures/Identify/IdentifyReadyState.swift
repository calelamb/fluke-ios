import FlukeReleaseB
import Observation

@MainActor
@Observable
final class IdentifyReadyState {
  let camera: IdentifyCameraCoordinator
  let model: IdentifyViewModel

  convenience init(
    online: Bool,
    service: any IdentifyServiceProtocol
  ) {
    self.init(
      online: online,
      service: service,
      camera: IdentifyCameraCoordinator()
    )
  }

  init(
    online: Bool,
    service: any IdentifyServiceProtocol,
    camera: IdentifyCameraCoordinator
  ) {
    self.camera = camera
    model = IdentifyViewModel(
      capability: true,
      online: online,
      media: camera,
      service: service
    )
  }
}
