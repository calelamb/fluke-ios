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
        MockURLProtocol.reset()
    }

    func test_fetchAll_consumesEveryPageAndEncodesOpaqueCursor() async throws {
        let requestCount = MockRequestCounter()
        MockURLProtocol.install { req in
            XCTAssertEqual(req.url?.path, "/api/v1/whales")
            let count = requestCount.increment()
            let isFirstPage = count == 1
            XCTAssertEqual(
                req.url?.absoluteString,
                isFirstPage
                    ? "http://localhost:4000/api/v1/whales"
                    : "http://localhost:4000/api/v1/whales?cursor=page%202%2Bnext%26tail"
            )
            let catalogId = isFirstPage ? "A1" : "A2"
            let pagination = isFirstPage
                ? #"{"hasMore":true,"nextCursor":"page 2+next&tail"}"#
                : #"{"hasMore":false,"nextCursor":null}"#
            let body = """
            {
              "items": [{
                "id":"wh_\(catalogId)","catalogId":"\(catalogId)","name":"Alpha",
                "ecotype":"UNKNOWN","pod":null,"sex":"UNKNOWN",
                "birthYear":null,"deathYear":null,"status":"UNKNOWN",
                "biography":null,"distinguishingMarks":null,"heroImageUrl":null,
                "notableEvents":[],"sourceCitations":[]
              }],
              "page":\(pagination)
            }
            """.data(using: .utf8)!
            return (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                body
            )
        }
        let whales = try await repo.fetchAll()
        XCTAssertEqual(whales.map(\.catalogId), ["A1", "A2"])
        XCTAssertEqual(requestCount.value, 2)
    }

    func test_fetchAll_rejectsHasMoreWithoutCursor() async {
        MockURLProtocol.install { req in
            let body = #"{"items":[],"page":{"hasMore":true,"nextCursor":null}}"#.data(using: .utf8)!
            return (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                body
            )
        }

        await XCTAssertThrowsErrorAsync(try await repo.fetchAll()) { error in
            XCTAssertEqual(error as? APIError, .invalidPagination)
        }
    }

    func test_fetchAll_rejectsTerminalPageWithCursorInsteadOfReturningItems() async {
        MockURLProtocol.install { req in
            let body = """
            {
              "items":[{
                "id":"wh_a","catalogId":"A1","name":"Alpha",
                "ecotype":"UNKNOWN","pod":null,"sex":"UNKNOWN",
                "birthYear":null,"deathYear":null,"status":"UNKNOWN",
                "biography":null,"distinguishingMarks":null,"heroImageUrl":null,
                "notableEvents":[],"sourceCitations":[]
              }],
              "page":{"hasMore":false,"nextCursor":"unexpected"}
            }
            """.data(using: .utf8)!
            return (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                body
            )
        }

        await XCTAssertThrowsErrorAsync(try await repo.fetchAll()) { error in
            XCTAssertEqual(error as? APIError, .invalidPagination)
        }
    }

    func test_fetchAll_rejectsRepeatedCursor() async {
        MockURLProtocol.install { req in
            let body = #"{"items":[],"page":{"hasMore":true,"nextCursor":"same"}}"#.data(using: .utf8)!
            return (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                body
            )
        }

        await XCTAssertThrowsErrorAsync(try await repo.fetchAll()) { error in
            XCTAssertEqual(error as? APIError, .invalidPagination)
        }
    }

    func test_fetchAll_rejectsResponsesBeyondMaximumPageCount() async {
        let requestCount = MockRequestCounter()
        MockURLProtocol.install { req in
            let count = requestCount.increment()
            let body = """
            {"items":[],"page":{"hasMore":true,"nextCursor":"cursor-\(count)"}}
            """.data(using: .utf8)!
            return (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                body
            )
        }

        await XCTAssertThrowsErrorAsync(try await repo.fetchAll()) { error in
            XCTAssertEqual(error as? APIError, .invalidPagination)
        }
        XCTAssertEqual(requestCount.value, PaginatedRepository.maximumPageCount)
    }

    func test_find_decodesWhaleProfile() async throws {
        let body = try FixtureLoader.data(named: "whale-detail")
        MockURLProtocol.install { req in
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

    func test_fetchTrack_unwrapsPointsFromWhaleTrackResponse() async throws {
        MockURLProtocol.install { req in
            XCTAssertEqual(req.url?.path, "/api/v1/whales/wh_a/track")
            let body = """
            {
              "whaleId":"wh_a","catalogId":"A1",
              "points":[{
                "id":"si_1","observedAt":"2026-04-20T17:45:00.000Z",
                "latitude":48.5163,"longitude":-123.1552,
                "locationName":"Lime Kiln","behaviorNotes":"travelling"
              }]
            }
            """.data(using: .utf8)!
            return (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                body
            )
        }
        let track = try await repo.fetchTrack(
            whaleId: "wh_a",
            from: Date(timeIntervalSince1970: 1_700_000_000),
            to: Date(timeIntervalSince1970: 1_700_086_400)
        )
        XCTAssertEqual(track.count, 1)
        XCTAssertEqual(track.first?.locationName, "Lime Kiln")
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
