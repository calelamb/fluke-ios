import FlukeKit
import FlukeReleaseB
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@Suite("Identification service")
struct IdentifyServiceTests {
  @Test("Rejects non-images and oversized decoded images before upload")
  func rejectsUnsafePhotos() throws {
    #expect(throws: IdentifyPhotoError.unsupportedFormat) {
      try IdentifyPhoto(bytes: Data("not a jpeg".utf8))
    }
    let oversized = try jpeg(width: 7_000, height: 7_000)
    #expect(throws: IdentifyPhotoError.decompressionLimit) {
      try IdentifyPhoto(bytes: oversized)
    }
  }

  @Test("Uploads one bounded JPEG and returns the top three ordered matches")
  func ordersTopThree() async throws {
    let transport = IdentifyTransport(
      response: .json(200, responseJSON(scores: [0.4, 0.91, 0.65, 0.2])))
    let service = IdentifyService(
      api: APIClient(
        baseURL: URL(string: "https://example.com")!, transport: transport
      ))

    let result = try await service.identify(photo: IdentifyPhoto(bytes: try jpeg()))

    #expect(result.matches.map(\.score) == [0.91, 0.65, 0.4])
    #expect(await transport.requests.count == 1)
    #expect(await transport.requests.first?.url?.path == "/api/v1/identify")
    #expect(
      await transport.requests.first?.value(forHTTPHeaderField: "Content-Type")?.hasPrefix(
        "multipart/form-data") == true)
  }

  @Test("Equal score and rank matches preserve response order")
  func stableTieOrdering() async throws {
    let tied =
      #"{"matches":[{"catalogId":"J2","name":"Second","score":0.8,"rank":1,"matchedReferencePhotoIds":["r2"],"explanation":"Visual overlap."},{"catalogId":"J1","name":"First","score":0.8,"rank":1,"matchedReferencePhotoIds":["r1"],"explanation":"Visual overlap."},{"catalogId":"J3","name":"Third","score":0.8,"rank":1,"matchedReferencePhotoIds":["r3"],"explanation":"Visual overlap."}],"confidenceBand":"medium","model":"model-v1","indexVersion":"index-v1","uploadUrl":null}"#
    let service = IdentifyService(
      api: APIClient(
        baseURL: URL(string: "https://example.com")!,
        transport: IdentifyTransport(response: .json(200, tied))
      ))

    let response = try await service.identify(photo: IdentifyPhoto(bytes: jpeg()))

    #expect(response.matches.map(\.catalogId) == ["J2", "J1", "J3"])
  }

  @Test("Rejects scores outside zero through one")
  func rejectsInvalidScores() async throws {
    let transport = IdentifyTransport(response: .json(200, responseJSON(scores: [1.01])))
    let service = IdentifyService(
      api: APIClient(
        baseURL: URL(string: "https://example.com")!, transport: transport
      ))
    let photo = try IdentifyPhoto(bytes: jpeg())

    await #expect(throws: IdentifyServiceError.invalidResponse) {
      try await service.identify(photo: photo)
    }
  }

  @Test("Rejects unsafe returned upload URLs")
  func rejectsUnsafeUploadURL() async throws {
    let json = responseJSON(scores: [0.8]).replacingOccurrences(
      of: #""uploadUrl":null"#,
      with: #""uploadUrl":"http://example.com/photo.jpg""#
    )
    let service = IdentifyService(
      api: APIClient(
        baseURL: URL(string: "https://example.com")!,
        transport: IdentifyTransport(response: .json(200, json))
      ))
    await #expect(throws: IdentifyServiceError.invalidResponse) {
      try await service.identify(photo: IdentifyPhoto(bytes: try jpeg()))
    }
  }

  @Test("Maps 501 to training and preserves cancellation")
  func mapsUnavailableAndCancellation() async throws {
    let training = IdentifyService(
      api: APIClient(
        baseURL: URL(string: "https://example.com")!,
        transport: IdentifyTransport(
          response: .json(501, #"{"error":{"code":"not_ready","message":"not ready"}}"#))
      ))
    await #expect(throws: IdentifyServiceError.training) {
      try await training.identify(photo: IdentifyPhoto(bytes: try jpeg()))
    }

    let cancelled = IdentifyService(
      api: APIClient(
        baseURL: URL(string: "https://example.com")!,
        transport: IdentifyTransport(response: .failure(CancellationError()))
      ))
    await #expect(throws: CancellationError.self) {
      try await cancelled.identify(photo: IdentifyPhoto(bytes: try jpeg()))
    }
  }

  @Test("Identification upload never retries a transient response-loss failure")
  func uploadDoesNotRetry() async throws {
    let transport = TransientIdentifyTransport()
    let service = IdentifyService(
      api: APIClient(
        baseURL: URL(string: "https://example.com")!, transport: transport
      ))

    await #expect(throws: APIError.transport) {
      try await service.identify(photo: IdentifyPhoto(bytes: try jpeg()))
    }
    #expect(await transport.requestCount == 1)
  }
}

private actor TransientIdentifyTransport: HTTPTransport {
  private(set) var requestCount = 0

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    requestCount += 1
    throw URLError(.networkConnectionLost)
  }
}

private actor IdentifyTransport: HTTPTransport {
  enum Result: @unchecked Sendable {
    case json(Int, String)
    case failure(Error)
  }

  private let response: Result
  private(set) var requests: [URLRequest] = []

  init(response: Result) { self.response = response }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    requests = requests + [request]
    switch response {
    case .json(let status, let json):
      return (
        Data(json.utf8),
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
      )
    case .failure(let error): throw error
    }
  }
}

private func responseJSON(scores: [Double]) -> String {
  let matches = scores.enumerated().map { index, score in
    #"{"catalogId":"J\#(index + 1)","name":"Whale \#(index + 1)","score":\#(score),"rank":\#(index + 1),"matchedReferencePhotoIds":["ref-\#(index + 1)"],"explanation":"Visual features overlap."}"#
  }.joined(separator: ",")
  return
    #"{"matches":[\#(matches)],"confidenceBand":"medium","model":"model-v1","indexVersion":"index-v1","uploadUrl":null}"#
}

private func jpeg(width: Int = 8, height: Int = 8) throws -> Data {
  let colorSpace = CGColorSpaceCreateDeviceRGB()
  let context = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8,
    bytesPerRow: width * 4, space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  )!
  let image = context.makeImage()!
  let output = NSMutableData()
  let destination = CGImageDestinationCreateWithData(
    output, UTType.jpeg.identifier as CFString, 1, nil
  )!
  CGImageDestinationAddImage(destination, image, nil)
  #expect(CGImageDestinationFinalize(destination))
  return output as Data
}
