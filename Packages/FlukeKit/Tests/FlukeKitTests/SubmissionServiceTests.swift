import Foundation
import FlukeKit
import FlukeReleaseB
import Testing

@Suite("Submission service")
struct SubmissionServiceTests {
  @Test("Creates one sighting then uploads photos with the receipt token")
  func createsThenUploads() async throws {
    let transport = SubmissionTransport(responses: [
      .json(201, #"{"ok":true,"id":"s-1","photoUploadToken":"token-1"}"#),
      .json(201, "{}"),
      .json(201, "{}"),
    ])
    let service = SubmissionService(api: APIClient(
      baseURL: URL(string: "https://example.com")!, transport: transport
    ))
    let payload = try SubmissionValidator.validate(.fixture(photoCount: 2))
    let photos = [ProcessedPhoto.fixture(1), .fixture(2)]

    let receipt = try await service.submit(payload: payload, photos: photos)

    #expect(receipt.id == "s-1")
    let requests = await transport.requests
    #expect(requests.map(\.url?.path) == [
      "/api/v1/sightings", "/api/v1/sightings/s-1/photos", "/api/v1/sightings/s-1/photos",
    ])
    #expect(requests.dropFirst().allSatisfy { $0.value(forHTTPHeaderField: "x-photo-upload-token") == "token-1" })
    #expect(requests.first?.value(forHTTPHeaderField: "Idempotency-Key") == payload.clientSubmissionID.uuidString)
    let body = try #require(requests.first?.httpBody)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(Set(json.keys) == [
      "clientSubmissionId", "observedAt", "latitude", "longitude", "locationName",
      "groupSize", "behaviorNotes", "observerEmail",
    ])
    #expect(json["clientSubmissionId"] as? String == payload.clientSubmissionID.uuidString)
    #expect(json["observedAt"] as? String == "2023-11-14T22:13:20.000Z")
    #expect(json["behaviorNotes"] as? String == "Traveling north")
    #expect(json["observerEmail"] as? String == "observer@example.com")
    #expect(json["photoCount"] == nil)
    #expect(json["existingReceipt"] == nil)
    #expect(requests[1].value(forHTTPHeaderField: "Idempotency-Key") == "\(payload.clientSubmissionID.uuidString):11111111-1111-1111-1111-111111111111")
    #expect(requests[2].value(forHTTPHeaderField: "Idempotency-Key") == "\(payload.clientSubmissionID.uuidString):22222222-2222-2222-2222-222222222222")
  }

  @Test("Partial photo retry skips sighting creation and reports only failed indices")
  func partialRetryIsIdempotent() async throws {
    let firstTransport = SubmissionTransport(responses: [
      .json(201, #"{"ok":true,"id":"s-1","photoUploadToken":"token-1"}"#),
      .json(201, "{}"),
      .json(503, #"{"error":"try later"}"#),
    ])
    let payload = try SubmissionValidator.validate(.fixture(photoCount: 2))
    let photos = [ProcessedPhoto.fixture(1), .fixture(2)]
    let firstService = SubmissionService(api: APIClient(
      baseURL: URL(string: "https://example.com")!, transport: firstTransport
    ))

    let partial = await #expect(throws: SubmissionServiceError.self) {
      try await firstService.submit(payload: payload, photos: photos)
    }
    guard case .partial(let receipt, let failedIndices) = partial else {
      Issue.record("Expected partial upload failure")
      return
    }
    #expect(failedIndices == [1])

    let retryTransport = SubmissionTransport(responses: [.json(201, "{}")])
    let retryService = SubmissionService(api: APIClient(
      baseURL: URL(string: "https://example.com")!, transport: retryTransport
    ))
    _ = try await retryService.submit(
      payload: payload.resuming(receipt: receipt), photos: [photos[1]]
    )
    #expect(await retryTransport.requests.count == 1)
    #expect(await retryTransport.requests.first?.url?.path == "/api/v1/sightings/s-1/photos")
    #expect(
      await retryTransport.requests.first?.value(forHTTPHeaderField: "Idempotency-Key")
        == "\(payload.clientSubmissionID.uuidString):22222222-2222-2222-2222-222222222222"
    )
  }

  @Test("Processed photo limit reserves enough bytes for multipart framing")
  func multipartBoundaryFitsMutationLimit() async throws {
    let transport = SubmissionTransport(responses: [
      .json(201, #"{"ok":true,"id":"s-1","photoUploadToken":"token-1"}"#),
      .json(201, "{}"),
    ])
    let service = SubmissionService(api: APIClient(
      baseURL: URL(string: "https://example.com")!, transport: transport
    ))
    let payload = try SubmissionValidator.validate(.fixture())
    let boundaryPhoto = ProcessedPhoto(
      bytes: Data(repeating: 1, count: SubmissionUploadLimits.maximumProcessedPhotoBytes),
      fileName: String(repeating: "a", count: 251) + ".jpg",
      idempotencyID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    )

    _ = try await service.submit(payload: payload, photos: [boundaryPhoto])
    #expect(await transport.requests.last?.httpBody?.count ?? 0 <= MutationBodyLimits.maximumBytes)
  }
}

private actor SubmissionTransport: HTTPTransport {
  struct Response: Sendable {
    let status: Int
    let data: Data
    static func json(_ status: Int, _ value: String) -> Response {
      Response(status: status, data: Data(value.utf8))
    }
  }

  private var remaining: [Response]
  private(set) var requests: [URLRequest] = []

  init(responses: [Response]) { remaining = responses }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    requests = requests + [request]
    let response = remaining.removeFirst()
    return (response.data, HTTPURLResponse(
      url: request.url!, statusCode: response.status, httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!)
  }
}

extension ProcessedPhoto {
  static func fixture(_ byte: UInt8) -> ProcessedPhoto {
    let id = byte == 1
      ? UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
      : UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    return ProcessedPhoto(bytes: Data(repeating: byte, count: 32), fileName: "photo.jpg", idempotencyID: id)
  }
}
