import Foundation
import Testing

@testable import FlukeKit

@Suite("Browse request safety")
struct BrowseRequestSafetyTests {
    private let from = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("Historical and track windows reject reversed and oversized ranges before HTTP")
    func rejectsInvalidWindows() async {
        let transport = RequestRecordingTransport(body: Data())
        let api = APIClient(baseURL: URL(string: "https://api.fluke.app")!, transport: transport)
        let historical = HistoricalSightingsRepository(api: api)
        let whales = WhalesRepository(api: api)

        await #expect(throws: APIError.invalidRequest) {
            try await historical.load(from: from.addingTimeInterval(1), to: from)
        }
        await #expect(throws: APIError.invalidRequest) {
            try await whales.loadTrack(
                whaleId: "whale-1",
                from: from,
                to: from.addingTimeInterval(367 * 86_400)
            )
        }
        #expect(await transport.requestedURLs.isEmpty)
    }

    @Test("External source filters are bounded before HTTP")
    func rejectsOversizedSourceFilter() async {
        let transport = RequestRecordingTransport(body: Data())
        let repository = SightingsRepository(
            api: APIClient(baseURL: URL(string: "https://api.fluke.app")!, transport: transport)
        )

        await #expect(throws: APIError.invalidRequest) {
            try await repository.loadExternal(source: String(repeating: "x", count: 501))
        }
        #expect(await transport.requestedURLs.isEmpty)
    }

    @Test("API requests reject dot-segment traversal")
    func rejectsDotSegmentPaths() {
        #expect(throws: APIError.invalidRequest) {
            try APIRequest(path: "/api/v1/../auth").url(
                relativeTo: URL(string: "https://api.fluke.app")!
            )
        }
        #expect(throws: APIError.invalidRequest) {
            try Endpoint.whale(id: "whale/../../admin")
        }
    }

    @Test("Prediction identifiers are encoded as query items")
    func predictionQueryEncoding() async throws {
        let transport = RequestRecordingTransport(body: try FixtureLoader.data(named: "prediction"))
        let repository = PredictionRepository(
            api: APIClient(baseURL: URL(string: "https://api.fluke.app")!, transport: transport)
        )

        _ = try await repository.load(subject: .whale(id: "whale a&b"), horizon: .h24)

        #expect(await transport.requestedURLs.first?.query == "whaleId=whale%20a%26b&horizon=24h")
    }

    @Test("Path identifiers reject traversal and encode safe reserved characters")
    func pathIdentifierSafety() async throws {
        let body = try FixtureLoader.data(named: "whale-detail")
        let transport = RequestRecordingTransport(body: body)
        let repository = WhalesRepository(
            api: APIClient(baseURL: URL(string: "https://api.fluke.app")!, transport: transport)
        )

        await #expect(throws: APIError.invalidRequest) {
            try await repository.find(byId: "../whale?admin=true")
        }
        _ = try? await repository.find(byId: "whale + one")

        #expect(await transport.requestedURLs.count == 1)
        #expect(await transport.requestedURLs.first?.absoluteString.contains("whale%20%2B%20one") == true)
    }

    @Test("A mismatched whale profile never poisons another identity cache")
    func rejectsMismatchedProfileIdentity() async throws {
        let original = String(decoding: try FixtureLoader.data(named: "whale-detail"), as: UTF8.self)
        let body = Data(original.replacingOccurrences(of: "fixture-whale-alpha", with: "other-whale").utf8)
        let transport = RequestRecordingTransport(body: body)
        let cache = MemoryBrowseCacheStore()
        let repository = WhalesRepository(
            api: APIClient(baseURL: URL(string: "https://api.fluke.app")!, transport: transport),
            cache: cache
        )

        let result = try await repository.loadProfile(id: "fixture-whale-alpha")

        guard case .failed(let failure) = result else {
            Issue.record("Expected identity mismatch failure")
            return
        }
        #expect(failure.code == "INVALID_RESPONSE")
        let key = BrowseCacheKey(resource: "whale-profile", identity: "fixture-whale-alpha")
        #expect(try await cache.load(WhaleProfile?.self, for: key) == nil)
    }

    @Test("A mismatched whale track never enters the requested identity cache")
    func rejectsMismatchedTrackIdentity() async throws {
        let original = String(decoding: try FixtureLoader.data(named: "whale-track"), as: UTF8.self)
        let body = Data(
            original
                .replacingOccurrences(of: "fixture-whale-alpha", with: "other-whale")
                .replacingOccurrences(of: "FX-001", with: "OTHER")
                .utf8
        )
        let transport = RequestRecordingTransport(body: body)
        let cache = MemoryBrowseCacheStore()
        let repository = WhalesRepository(
            api: APIClient(baseURL: URL(string: "https://api.fluke.app")!, transport: transport),
            cache: cache
        )

        let result = try await repository.loadTrack(
            whaleId: "fixture-whale-alpha",
            from: from,
            to: from.addingTimeInterval(86_400)
        )

        guard case .failed(let failure) = result else {
            Issue.record("Expected track identity mismatch failure")
            return
        }
        #expect(failure.code == "INVALID_RESPONSE")
    }
}

private actor RequestRecordingTransport: HTTPTransport {
    private let body: Data
    private(set) var requestedURLs: [URL] = []

    init(body: Data) {
        self.body = body
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else { throw URLError(.badURL) }
        requestedURLs = requestedURLs + [url]
        return (
            body,
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }
}
