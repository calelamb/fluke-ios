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

  @Test("Personal sightings drain every cursor page and preserve server order")
  func loadAllPages() async throws {
    let transport = LogbookTransport(responses: [
      nil: .init(
        status: 200,
        body: Self.page(
          items: [Self.item(id: "newest", observedAt: "2026-07-18T15:00:00.000Z")],
          hasMore: true,
          nextCursor: "opaque cursor/+="
        )),
      "opaque cursor/+=": .init(
        status: 200,
        body: Self.page(
          items: [Self.item(id: "oldest", observedAt: "2026-07-16T15:00:00.000Z")],
          hasMore: false,
          nextCursor: nil
        )),
    ])
    let repository = LogbookRepository(
      api: APIClient(
        baseURL: try #require(URL(string: "https://api.fluke.test")),
        transport: transport
      ))

    let entries = try await repository.load()

    #expect(entries.map(\.id) == ["newest", "oldest"])
    let requests = await transport.requests
    #expect(requests.count == 2)
    #expect(requests[0].url?.query == nil)
    let secondRequest = try #require(requests.dropFirst().first)
    #expect(
      URLComponents(url: try #require(secondRequest.url), resolvingAgainstBaseURL: false)?
        .queryItems == [URLQueryItem(name: "cursor", value: "opaque cursor/+=")])
  }

  @Test("Personal sightings reject a repeated cursor")
  func repeatedCursor() async throws {
    let repeated = Self.page(items: [], hasMore: true, nextCursor: "same")
    let transport = LogbookTransport(responses: [
      nil: .init(status: 200, body: repeated),
      "same": .init(status: 200, body: repeated),
    ])
    let repository = LogbookRepository(
      api: APIClient(
        baseURL: try #require(URL(string: "https://api.fluke.test")),
        transport: transport
      ))

    await #expect(throws: APIError.invalidPagination) {
      try await repository.load()
    }
    #expect(await transport.requests.count == 2)
  }

  @Test("Personal sightings reject cursors above the canonical bound")
  func oversizedCursor() async throws {
    let transport = LogbookTransport(
      status: 200,
      body: Self.page(
        items: [],
        hasMore: true,
        nextCursor: String(repeating: "🐋", count: 257)
      ))
    let repository = LogbookRepository(
      api: APIClient(
        baseURL: try #require(URL(string: "https://api.fluke.test")),
        transport: transport
      ))

    await #expect(throws: APIError.invalidPagination) {
      try await repository.load()
    }
    #expect(await transport.requests.count == 1)
  }

  @Test("Personal sightings reject pages above the canonical item cap")
  func oversizedPage() async throws {
    let items = (0...100).map {
      Self.item(id: "sighting-\($0)", observedAt: "2026-07-17T15:00:00.000Z")
    }
    let repository = LogbookRepository(
      api: APIClient(
        baseURL: try #require(URL(string: "https://api.fluke.test")),
        transport: LogbookTransport(
          status: 200,
          body: Self.page(items: items, hasMore: false, nextCursor: nil)
        )
      ))

    await #expect(throws: APIError.invalidPagination) {
      try await repository.load()
    }
  }

  @Test("Personal sightings stop before requesting beyond the canonical page cap")
  func pageCap() async throws {
    let responses = [String?: LogbookTransport.Response](
      uniqueKeysWithValues: (0..<100).map { index in
        let requestCursor: String? = index == 0 ? nil : "cursor-\(index)"
        return (
          requestCursor,
          .init(
            status: 200,
            body: Self.page(items: [], hasMore: true, nextCursor: "cursor-\(index + 1)")
          )
        )
      })
    let transport = LogbookTransport(responses: responses)
    let repository = LogbookRepository(
      api: APIClient(
        baseURL: try #require(URL(string: "https://api.fluke.test")),
        transport: transport
      ))

    await #expect(throws: APIError.invalidPagination) {
      try await repository.load()
    }
    #expect(await transport.requests.count == 100)
  }

  @Test("Personal sightings require the exact owner DTO")
  func exactOwnerDTO() async throws {
    let item = Self.item(id: "pending-1", observedAt: "2026-07-17T15:00:00.000Z")
      .replacingOccurrences(of: #""status":"PENDING""#, with: #""status":"PENDING","extra":true"#)
    let repository = LogbookRepository(
      api: APIClient(
        baseURL: try #require(URL(string: "https://api.fluke.test")),
        transport: LogbookTransport(
          status: 200,
          body: Self.page(items: [item], hasMore: false, nextCursor: nil)
        )
      ))

    await #expect(throws: APIError.self) {
      try await repository.load()
    }
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

  private static func page(items: [String], hasMore: Bool, nextCursor: String?) -> String {
    let cursor = nextCursor.map { #""\#($0)""# } ?? "null"
    return
      #"{"items":[\#(items.joined(separator: ","))],"page":{"hasMore":\#(hasMore),"nextCursor":\#(cursor)}}"#
  }

  private static func item(id: String, observedAt: String) -> String {
    #"{"id":"\#(id)","observedAt":"\#(observedAt)","latitude":48.1,"longitude":-122.7,"locationName":null,"createdAt":"2024-07-18T16:00:00.000Z","ecotypeGuess":null,"groupSize":null,"behaviorNotes":null,"photoCount":0,"rejectionReason":null,"status":"PENDING"}"#
  }
}

private actor LogbookTransport: HTTPTransport {
  struct Response: Sendable {
    let status: Int
    let body: String
  }

  private let responses: [String?: Response]
  private(set) var requests: [URLRequest] = []
  var lastRequest: URLRequest? { requests.last }

  init(status: Int, body: String) {
    responses = [nil: Response(status: status, body: body)]
  }

  init(responses: [String?: Response]) {
    self.responses = responses
  }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    requests = requests + [request]
    let cursor = request.url
      .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
      .queryItems?
      .first(where: { $0.name == "cursor" })?
      .value
    let selected = try #require(responses[cursor])
    let response = try #require(
      HTTPURLResponse(
        url: request.url ?? URL(fileURLWithPath: "/"),
        statusCode: selected.status,
        httpVersion: nil,
        headerFields: nil
      ))
    return (Data(selected.body.utf8), response)
  }
}
