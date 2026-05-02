import XCTest
@testable import FlukeKit

final class WhalesRepositoryTests: XCTestCase {

    private var apiClient: APIClient!
    private var repo: WhalesRepository!

    override func setUp() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        apiClient = APIClient(baseURL: URL(string: "http://localhost:4000")!, session: session)
        repo = WhalesRepository(api: apiClient)
    }

    override func tearDown() async throws {
        MockURLProtocol.handler = nil
    }

    func test_fetchAll_decodesArrayOfWhales() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.url?.path, "/api/v1/whales")
            let body = """
            [{
              "id":"wh_a","catalogId":"J35","name":"Tahlequah","ecotype":"RESIDENT",
              "pod":"J","biography":null,"heroImageUrl":null,
              "createdAt":"2026-01-01T00:00:00.000Z","updatedAt":"2026-01-01T00:00:00.000Z"
            }]
            """.data(using: .utf8)!
            return (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                body
            )
        }
        let whales = try await repo.fetchAll()
        XCTAssertEqual(whales.count, 1)
        XCTAssertEqual(whales.first?.catalogId, "J35")
    }

    func test_fetchTrack_decodesArrayOfTrackPoints() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.url?.path, "/api/v1/whales/wh_a/track")
            let body = """
            [{
              "id":"si_1","observedAt":"2026-04-20T17:45:00.000Z",
              "latitude":48.5163,"longitude":-123.1552,
              "locationName":"Lime Kiln","behaviorNotes":"travelling"
            }]
            """.data(using: .utf8)!
            return (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                body
            )
        }
        let track = try await repo.fetchTrack(whaleId: "wh_a")
        XCTAssertEqual(track.count, 1)
        XCTAssertEqual(track.first?.locationName, "Lime Kiln")
    }
}
