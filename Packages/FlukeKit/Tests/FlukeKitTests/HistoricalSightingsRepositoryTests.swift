import XCTest
@testable import FlukeKit

final class HistoricalSightingsRepositoryTests: XCTestCase {

    private var apiClient: APIClient!
    private var repo: HistoricalSightingsRepository!

    override func setUp() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        apiClient = APIClient(baseURL: URL(string: "http://localhost:4000")!, session: session)
        repo = HistoricalSightingsRepository(api: apiClient)
    }

    override func tearDown() async throws {
        MockURLProtocol.handler = nil
    }

    func test_fetch_unwrapsHistoricalSightingsFromPaginatedResponse() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.url?.path, "/api/v1/sightings/historical")
            let body = """
            {
              "items":[{
                "id":"si_1","observedAt":"2026-04-20T17:45:00.000Z",
                "latitude":48.5163,"longitude":-123.1552,
                "locationName":"Lime Kiln","ecotypeGuess":"RESIDENT",
                "whaleIds":["wh_a","wh_b"]
              }],
              "page":{"hasMore":false,"nextCursor":null}
            }
            """.data(using: .utf8)!
            return (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                body
            )
        }
        let sightings = try await repo.fetch(from: nil, to: nil, pod: nil, whaleId: nil)
        XCTAssertEqual(sightings.count, 1)
        XCTAssertEqual(sightings.first?.whaleIds, ["wh_a", "wh_b"])
    }

    func test_fetch_passesPodFilter() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.url?.query, "pod=J")
            return (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                "{\"items\":[],\"page\":{\"hasMore\":false,\"nextCursor\":null}}".data(using: .utf8)!
            )
        }
        _ = try await repo.fetch(from: nil, to: nil, pod: .j, whaleId: nil)
    }
}
