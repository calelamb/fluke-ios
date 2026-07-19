import CoreVideo
import FlukeFeatures
import FlukeKit
import FlukeML
import Foundation
import ImageIO
import Testing

@testable import Fluke

@MainActor
@Suite("On-device identification network boundary")
struct IdentificationNetworkBoundaryTests {
  private static let forbiddenSourceTerms = [
    "IdentifyService",
    "IdentifyPhoto",
    "ReleaseBEndpoint.identify",
    "/api/v1/identify",
  ]

  @Test("shipping sources cannot compose or address server identification")
  func sourceBoundary() throws {
    let roots = [
      Self.repositoryRoot.appendingPathComponent("App/Fluke"),
      Self.repositoryRoot.appendingPathComponent("Packages/FlukeKit/Sources"),
      Self.repositoryRoot.appendingPathComponent("Packages/FlukeFeatures/Sources"),
    ]
    let source = try roots.flatMap(Self.swiftSources).joined(separator: "\n")

    for forbidden in Self.forbiddenSourceTerms {
      #expect(!source.contains(forbidden), "Shipping source contains \(forbidden)")
    }

    let localPipelineSource = try [
      Self.repositoryRoot.appendingPathComponent(
        "Packages/FlukeFeatures/Sources/FlukeFeatures/Identify"),
      Self.repositoryRoot.appendingPathComponent("Packages/FlukeML/Sources"),
    ].flatMap(Self.swiftSources).joined(separator: "\n")
    for forbidden in ["URLSession", "APIClient", "HTTPTransport", "MultipartForm"] {
      #expect(!localPipelineSource.contains(forbidden))
    }
  }

  @Test("built shipping artifacts contain no server identification endpoint")
  func artifactBoundary() throws {
    let bundleURL = Bundle.main.bundleURL
    let files = try FileManager.default.subpathsOfDirectory(atPath: bundleURL.path)
      .map { bundleURL.appendingPathComponent($0) }
      .filter { !$0.path.contains("/PlugIns/") }

    for file in files
    where (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    {
      let data = try Data(contentsOf: file, options: .mappedIfSafe)
      #expect(data.range(of: Data("/api/v1/identify".utf8)) == nil)
    }
  }

  @Test("camera frames and local candidates never invoke the injected URL session")
  func runtimeBoundary() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [UnexpectedIdentificationURLProtocol.self]
    let environment = try AppEnvironment.make(
      apiBaseURLString: "https://api.fluke.test",
      configuration: .release,
      session: URLSession(configuration: configuration)
    )
    let identifier = BoundaryLocalIdentifier()
    let media = BoundaryMedia()
    let capability = IdentificationComposition.resolve(
      capabilities: .available(
        .init(
          accounts: true,
          identification: true,
          identificationMode: .onDevice,
          submissions: true
        )
      ),
      cachedMode: nil,
      localIdentifier: .available(identifier)
    )
    let model = IdentifyViewModel(capability: capability, media: media)
    _ = environment.apiBaseURL

    await model.openCamera()
    await media.yield(try Self.frame())
    await identifier.waitUntilCalled()

    #expect(await identifier.callCount == 1)
    #expect(model.result?.provisional.first?.referencePhotoIDs == ["local-reference"])
  }
}

extension IdentificationNetworkBoundaryTests {
  static var repositoryRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  static func swiftSources(at root: URL) throws -> [String] {
    try FileManager.default.subpathsOfDirectory(atPath: root.path)
      .filter { $0.hasSuffix(".swift") }
      .map { try String(contentsOf: root.appendingPathComponent($0), encoding: .utf8) }
  }

  static func frame() throws -> CameraFrame {
    var buffer: CVPixelBuffer?
    guard
      CVPixelBufferCreate(
        kCFAllocatorDefault,
        2,
        2,
        kCVPixelFormatType_32BGRA,
        nil,
        &buffer
      ) == kCVReturnSuccess,
      let buffer
    else { throw LocalIdentifierError.invalidPixelBuffer }
    return try CameraFrame(pixelBuffer: buffer, orientation: .up)
  }
}

private final class UnexpectedIdentificationURLProtocol: URLProtocol {
  override class func canInit(with _: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    Issue.record("On-device identification attempted network I/O")
    client?.urlProtocol(self, didFailWithError: URLError(.dataNotAllowed))
  }
  override func stopLoading() {}
}

@MainActor
private final class BoundaryMedia: IdentifyMediaProviding {
  private let channel = AsyncStream<CameraFrame>.makeStream(bufferingPolicy: .bufferingNewest(0))
  let cameraState = PhotoCameraState.available
  private(set) var isCameraPresented = false
  var frames: AsyncStream<CameraFrame> { channel.stream }

  func openCamera() async { isCameraPresented = true }

  func yield(_ frame: CameraFrame) async {
    for _ in 0..<100 {
      if case .enqueued = channel.continuation.yield(frame) { return }
      await Task.yield()
    }
    Issue.record("Frame consumer never requested demand")
  }
}

private actor BoundaryLocalIdentifier: LocalIdentifying {
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private(set) var callCount = 0

  func identify(frame _: CameraFrame) -> LocalIdentificationState {
    callCount += 1
    let ready = waiters
    waiters = []
    for waiter in ready { waiter.resume() }
    let match = LocalMatch(
      catalogID: "J35",
      whaleID: "canonical-whale",
      score: 0.8,
      rank: 1,
      matchedReferencePhotoIDs: ["local-reference"]
    )
    return LocalIdentificationState(
      matches: [match],
      prominent: nil,
      artifact: LocalIdentificationArtifact(
        manifestVersion: "manifest",
        modelVersion: "model",
        indexVersion: "index"
      )
    )
  }

  func waitUntilCalled() async {
    guard callCount == 0 else { return }
    await withCheckedContinuation { waiters.append($0) }
  }
}
