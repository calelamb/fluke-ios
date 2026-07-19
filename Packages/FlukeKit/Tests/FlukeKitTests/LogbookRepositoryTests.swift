import Foundation
import Testing

@testable import FlukeKit
@testable import FlukeReleaseB

struct LogbookRepositoryTests {
  @Test("Personal sightings use the authenticated logbook endpoint")
  func load() async throws {
    let transport = LogbookTransport(status: 200, body: Self.response)
    let repository = LogbookRepository(
      api: APIClient(
        baseURL: try #require(URL(string: "https://api.fluke.test")),
        transport: transport
      ))

    let entries = try await repository.load()

    #expect(entries.map(\.status) == [.pending, .approved])
    #expect(entries.first?.locationName == "Admiralty Inlet")
    #expect(entries.first?.createdAt == Date(timeIntervalSince1970: 1_721_318_400))
    #expect(entries.first?.photoCount == 2)
    #expect(entries.first?.rejectionReason == nil)
    let request = try #require(await transport.lastRequest)
    #expect(request.httpMethod == "GET")
    #expect(request.url?.path == ReleaseBEndpoint.mySightings)
  }

  @Test("Unauthorized personal sightings remain an explicit session error")
  func unauthorized() async throws {
    let repository = LogbookRepository(
      api: APIClient(
        baseURL: try #require(URL(string: "https://api.fluke.test")),
        transport: LogbookTransport(status: 401, body: "")
      ))

    await #expect(throws: APIError.unauthorized) {
      try await repository.load()
    }
  }

  private static let response = #"""
    {
      "items": [
        {
          "id": "pending-1",
          "observedAt": "2026-07-17T15:00:00.000Z",
          "latitude": 48.1,
          "longitude": -122.7,
          "locationName": "Admiralty Inlet",
          "createdAt": "2024-07-18T16:00:00.000Z",
          "ecotypeGuess": "BIGGS",
          "groupSize": 3,
          "behaviorNotes": null,
          "photoCount": 2,
          "rejectionReason": null,
          "status": "PENDING"
        },
        {
          "id": "approved-1",
          "observedAt": "2026-07-16T15:00:00.000Z",
          "latitude": 48.2,
          "longitude": -122.8,
          "locationName": null,
          "createdAt": "2024-07-17T16:00:00.000Z",
          "ecotypeGuess": null,
          "groupSize": null,
          "behaviorNotes": null,
          "photoCount": 0,
          "rejectionReason": null,
          "status": "APPROVED"
        }
      ],
      "page": {"hasMore": false, "nextCursor": null}
    }
    """#
}

private actor LogbookTransport: HTTPTransport {
  private let status: Int
  private let body: Data
  private(set) var lastRequest: URLRequest?

  init(status: Int, body: String) {
    self.status = status
    self.body = Data(body.utf8)
  }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    lastRequest = request
    let response = try #require(
      HTTPURLResponse(
        url: request.url ?? URL(fileURLWithPath: "/"),
        statusCode: status,
        httpVersion: nil,
        headerFields: nil
      ))
    return (body, response)
  }
}
