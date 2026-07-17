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
        let body = try FixtureLoader.data(named: "whales")
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.url?.path, "/api/v1/whales")
            return (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                body
            )
        }
        let whales = try await repo.fetchAll()
        XCTAssertEqual(whales.count, 1)
        XCTAssertEqual(whales.first?.catalogId, "FX-001")
    }

    func test_find_decodesWhaleProfile() async throws {
        let body = try FixtureLoader.data(named: "whale-detail")
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.url?.path, "/api/v1/whales/fixture-whale-alpha")
            return (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                body
            )
        }

        let whale = try await repo.find(byId: "fixture-whale-alpha")
        XCTAssertEqual(whale?.mother?.catalogId, "FX-000")
        XCTAssertEqual(whale?.recentSightings.first?.id, "fixture-sighting-1")
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
