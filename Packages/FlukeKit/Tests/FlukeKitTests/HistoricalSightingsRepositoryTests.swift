import XCTest
@testable import FlukeKit

final class HistoricalSightingsRepositoryTests: XCTestCase {
    private let from = Date(timeIntervalSince1970: 1_700_000_000)
    private let to = Date(timeIntervalSince1970: 1_700_086_400)

    private var apiClient: APIClient!
    private var repo: HistoricalSightingsRepository!
    private var mockSession: MockURLProtocolSession!

    override func setUp() async throws {
        mockSession = MockURLProtocolSession()
        let session = URLSession(configuration: mockSession.configuration)
        apiClient = APIClient(baseURL: URL(string: "http://localhost:4000")!, session: session)
        repo = HistoricalSightingsRepository(api: apiClient)
    }

    override func tearDown() async throws {
        mockSession.reset()
        mockSession = nil
    }

    func test_fetch_unwrapsHistoricalSightingsFromPaginatedResponse() async throws {
        mockSession.install { req in
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
        let sightings = try await repo.fetch(from: from, to: to, pod: nil, whaleId: nil)
        XCTAssertEqual(sightings.count, 1)
        XCTAssertEqual(sightings.first?.whaleIds, ["wh_a", "wh_b"])
    }

    func test_fetch_passesPodFilter() async throws {
        mockSession.install { req in
            XCTAssertEqual(req.url?.queryItemsDictionary["pod"], "J")
            return (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                "{\"items\":[],\"page\":{\"hasMore\":false,\"nextCursor\":null}}".data(using: .utf8)!
            )
        }
        _ = try await repo.fetch(from: from, to: to, pod: .j, whaleId: nil)
    }

    func test_fetch_consumesEveryPageWhilePreservingEncodedFilters() async throws {
        let requestCount = MockRequestCounter()
        mockSession.install { req in
            let count = requestCount.increment()
            XCTAssertEqual(req.url?.path, "/api/v1/sightings/historical")
            XCTAssertEqual(req.url?.queryItemsDictionary["pod"], "J")
            XCTAssertEqual(req.url?.queryItemsDictionary["whaleId"], "whale a&b")
            XCTAssertEqual(req.url?.queryItemsDictionary["cursor"], count == 1 ? nil : "next+page&two")
            let sightingId = count == 1 ? "si_1" : "si_2"
            let pagination = count == 1
                ? #"{"hasMore":true,"nextCursor":"next+page&two"}"#
                : #"{"hasMore":false,"nextCursor":null}"#
            let body = """
            {
              "items":[{
                "id":"\(sightingId)","observedAt":"2026-04-20T17:45:00.000Z",
                "latitude":48.5163,"longitude":-123.1552,
                "locationName":"Lime Kiln","ecotypeGuess":"RESIDENT","whaleIds":[]
              }],
              "page":\(pagination)
            }
            """.data(using: .utf8)!
            return (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                body
            )
        }

        let sightings = try await repo.fetch(from: from, to: to, pod: .j, whaleId: "whale a&b")

        XCTAssertEqual(sightings.map(\.id), ["si_1", "si_2"])
        XCTAssertEqual(requestCount.value, 2)
    }
}

private extension URL {
    var queryItemsDictionary: [String: String] {
        Dictionary(uniqueKeysWithValues: (URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .compactMap { item in item.value.map { (item.name, $0) } })
    }
}
