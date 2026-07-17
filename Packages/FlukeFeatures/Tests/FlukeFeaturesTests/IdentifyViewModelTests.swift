import CoreGraphics
import FlukeFeatures
import FlukeKit
import FlukeReleaseB
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@MainActor
@Suite("Identification state machine")
struct IdentifyViewModelTests {
  @Test("Disabled identification never requests media or uploads")
  func disabledDoesNoWork() async {
    let media = RecordingMediaAuthorization()
    let service = RecordingIdentifyService()
    let model = IdentifyViewModel(capability: false, online: true, media: media, service: service)

    await model.openCamera()

    #expect(media.requestCount == 0)
    #expect(await service.requestCount == 0)
    #expect(model.availability == .training)
    #expect(model.unavailableMessage == IdentifyViewModel.trainingMessage)
  }

  @Test("Ready identification explains offline state without requesting media")
  func offlineDoesNoWork() async {
    let media = RecordingMediaAuthorization()
    let service = RecordingIdentifyService()
    let model = IdentifyViewModel(capability: true, online: false, media: media, service: service)

    await model.openCamera()

    #expect(model.availability == .needsInternet)
    #expect(media.requestCount == 0)
    #expect(await service.requestCount == 0)
  }

  @Test("501 returns to honest training state")
  func mapsTraining() async {
    let media = RecordingMediaAuthorization(photo: .fixture)
    let service = RecordingIdentifyService(result: .failure(IdentifyServiceError.training))
    let model = IdentifyViewModel(capability: true, online: true, media: media, service: service)

    await model.openCamera()

    #expect(model.availability == .training)
    #expect(model.matches.isEmpty)
  }

  @Test("Cancellation returns to ready and never invents results")
  func cancellation() async {
    let media = RecordingMediaAuthorization(photo: .fixture)
    let service = RecordingIdentifyService(result: .failure(CancellationError()))
    let model = IdentifyViewModel(capability: true, online: true, media: media, service: service)

    await model.openCamera()

    #expect(model.availability == .ready)
    #expect(model.matches.isEmpty)
    #expect(model.errorMessage == nil)
  }

  @Test("Results retain permanent disclaimer and feedback stays disabled")
  func honestResults() async {
    let response = IdentifyResponse.fixture
    let media = RecordingMediaAuthorization(photo: .fixture)
    let service = RecordingIdentifyService(result: .success(response))
    let model = IdentifyViewModel(capability: true, online: true, media: media, service: service)

    await model.openCamera()

    #expect(model.matches == response.matches)
    #expect(model.disclaimer == "Visual similarity, not a confirmed ID")
    #expect(!model.isWrongMatchFeedbackEnabled)
  }

  @Test("Camera and comparison failures use bounded safe copy")
  func safeFailures() async {
    let cameraFailure = IdentifyViewModel(
      capability: true,
      online: true,
      media: RecordingMediaAuthorization(result: .failure(TestError.failure)),
      service: RecordingIdentifyService()
    )
    await cameraFailure.openCamera()
    #expect(
      cameraFailure.errorMessage
        == "Fluke could not open the camera. Please try a photo from your library.")

    let comparisonFailure = IdentifyViewModel(
      capability: true,
      online: true,
      media: RecordingMediaAuthorization(photo: .fixture),
      service: RecordingIdentifyService(result: .failure(TestError.failure))
    )
    await comparisonFailure.openCamera()
    #expect(
      comparisonFailure.errorMessage == "Fluke could not compare this photo. Please try again.")
    #expect(comparisonFailure.matches.isEmpty)
  }

  @Test("Offline response fails closed and invalid photos clear prior results")
  func offlineAndInvalidPhoto() async {
    let model = IdentifyViewModel(
      capability: true,
      online: true,
      media: RecordingMediaAuthorization(photo: .fixture),
      service: RecordingIdentifyService(result: .failure(APIError.offline))
    )
    await model.openCamera()
    #expect(model.availability == .needsInternet)
    #expect(model.unavailableMessage?.contains("internet connection") == true)

    model.reportInvalidPhoto()
    #expect(model.errorMessage == "Choose a valid JPEG photo with a clearly visible dorsal fin.")
    #expect(model.matches.isEmpty)
  }

  @Test(
    "Denied, restricted, and unavailable cameras show safe copy without presenting",
    arguments: [
      PhotoSelectionPresentation.cameraState(for: .denied),
      PhotoSelectionPresentation.cameraState(for: .restricted),
      PhotoSelectionPresentation.cameraState(for: .unavailable),
    ])
  func unavailableCameraDoesNoWork(state: PhotoCameraState) async {
    let media = RecordingMediaAuthorization(cameraState: state, photo: .fixture)
    let service = RecordingIdentifyService()
    let model = IdentifyViewModel(
      capability: true, online: true, media: media, service: service
    )

    await model.openCamera()

    #expect(model.cameraState == state)
    #expect(media.requestCount == 0)
    #expect(await service.requestCount == 0)
    guard case .unavailable(let message) = model.cameraState else {
      Issue.record("Expected unavailable camera copy")
      return
    }
    #expect(!message.isEmpty && message.count < 160)
  }
}

@MainActor
private final class RecordingMediaAuthorization: IdentifyMediaProviding {
  private let result: Result<IdentifyPhoto?, Error>
  let cameraState: PhotoCameraState
  private(set) var requestCount = 0

  init(cameraState: PhotoCameraState = .available, photo: IdentifyPhoto? = nil) {
    self.cameraState = cameraState
    result = .success(photo)
  }
  init(
    cameraState: PhotoCameraState = .available,
    result: Result<IdentifyPhoto?, Error>
  ) {
    self.cameraState = cameraState
    self.result = result
  }

  func requestCameraPhoto() async throws -> IdentifyPhoto? {
    requestCount += 1
    return try result.get()
  }
}

private enum TestError: Error { case failure }

private actor RecordingIdentifyService: IdentifyServiceProtocol {
  private let result: Result<IdentifyResponse, Error>
  private(set) var requestCount = 0

  init(result: Result<IdentifyResponse, Error> = .success(.fixture)) {
    self.result = result
  }

  func identify(photo: IdentifyPhoto) async throws -> IdentifyResponse {
    requestCount += 1
    return try result.get()
  }
}

extension IdentifyPhoto {
  fileprivate static var fixture: IdentifyPhoto {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
      data: nil, width: 8, height: 8, bitsPerComponent: 8,
      bytesPerRow: 32, space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let output = NSMutableData()
    let destination = CGImageDestinationCreateWithData(
      output, UTType.jpeg.identifier as CFString, 1, nil
    )!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(destination))
    return try! IdentifyPhoto(bytes: output as Data)
  }
}

extension IdentifyResponse {
  fileprivate static var fixture: IdentifyResponse {
    IdentifyResponse(
      matches: [
        IdentifyMatch(
          catalogId: "J35", name: "Tahlequah", score: 0.91, rank: 1,
          matchedReferencePhotoIds: ["reference"], explanation: "Visual features overlap."
        )
      ],
      confidenceBand: .high, model: "model-v1", indexVersion: "index-v1", uploadURL: nil
    )
  }
}
