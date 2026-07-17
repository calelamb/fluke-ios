import Foundation
import Testing

@testable import FlukeKit

@Suite("Release A browse repositories")
struct BrowseRepositoriesTests {
    @Test("Sightings load canonical approved and bounded external feeds")
    func sightings() async throws {
        let transport = try FixtureRoutingTransport(fixtures: [
            Endpoint.sightings: "sightings",
            Endpoint.externalSightings: "external-sightings",
        ])
        let repository = SightingsRepository(api: api(transport))

        guard case .fresh(let approved, _) = try await repository.loadApproved() else {
            Issue.record("Expected fresh approved sightings")
            return
        }
        guard case .fresh(let external, _) = try await repository.loadExternal(
            source: "OBIS SEAMAP",
            sinceDays: 99
        ) else {
            Issue.record("Expected fresh external sightings")
            return
        }

        #expect(approved.first?.id == "fixture-sighting-1")
        #expect(external.first?.id == "external-sighting-1")
        let urls = await transport.requestedURLs
        #expect(urls.last?.query?.contains("sinceDays=31") == true)
        #expect(urls.last?.query?.contains("source=OBIS%20SEAMAP") == true)
    }

    @Test("Whales load catalog, profile, and explicit-date track")
    func whales() async throws {
        let transport = try FixtureRoutingTransport(fixtures: [
            Endpoint.whales: "whales",
            Endpoint.whale(id: "fixture-whale-alpha"): "whale-detail",
            Endpoint.whaleTrack(id: "fixture-whale-alpha"): "whale-track",
        ])
        let repository = WhalesRepository(api: api(transport))

        guard case .fresh(let catalog, _) = try await repository.loadCatalog() else {
            Issue.record("Expected fresh catalog")
            return
        }
        guard case .fresh(let profile, _) = try await repository.loadProfile(
            id: "fixture-whale-alpha"
        ) else {
            Issue.record("Expected fresh whale profile")
            return
        }
        guard case .fresh(let track, _) = try await repository.loadTrack(
            whaleId: "fixture-whale-alpha",
            from: Date(timeIntervalSince1970: 1_000),
            to: Date(timeIntervalSince1970: 2_000)
        ) else {
            Issue.record("Expected fresh whale track")
            return
        }

        #expect(catalog.first?.catalogId == "FX-001")
        #expect(profile?.id == "fixture-whale-alpha")
        #expect(track.first?.id == "fixture-sighting-1")
        let trackURL = await transport.requestedURLs.last
        #expect(trackURL?.query?.contains("from=") == true)
        #expect(trackURL?.query?.contains("to=") == true)
    }

    @Test("Historical sightings load a bounded public query")
    func historical() async throws {
        let transport = try FixtureRoutingTransport(fixtures: [
            Endpoint.historicalSightings: "historical-sightings",
        ])
        let repository = HistoricalSightingsRepository(api: api(transport))

        guard case .fresh(let sightings, _) = try await repository.load(
            from: Date(timeIntervalSince1970: 1_000),
            to: Date(timeIntervalSince1970: 2_000),
            pod: .j
        ) else {
            Issue.record("Expected fresh historical sightings")
            return
        }

        #expect(sightings.first?.id == "historical-sighting-1")
        let url = await transport.requestedURLs.first
        #expect(url?.query?.contains("pod=J") == true)
    }

    @Test("Predictions load canonical data and treat 404 as true empty")
    func predictions() async throws {
        let successful = try FixtureRoutingTransport(fixtures: [Endpoint.predict: "prediction"])
        let repository = PredictionRepository(api: api(successful))

        guard case .fresh(let prediction, _) = try await repository.load(
            subject: .whale(id: "fixture-whale-alpha"),
            horizon: .h24
        ) else {
            Issue.record("Expected fresh prediction")
            return
        }
        #expect(prediction?.cells.first?.probability == 0.72)

        let missing = FixtureRoutingTransport(routes: [
            Endpoint.predict: (404, Data(#"{"code":"NOT_FOUND","message":"Not found","retryable":false}"#.utf8)),
        ])
        let missingRepository = PredictionRepository(api: api(missing))
        guard case .empty = try await missingRepository.load(
            subject: .pod(.j),
            horizon: .h24
        ) else {
            Issue.record("Expected a true empty prediction")
            return
        }
    }

    private func api(_ transport: FixtureRoutingTransport) -> APIClient {
        APIClient(baseURL: URL(string: "https://api.fluke.app")!, transport: transport)
    }
}

private actor FixtureRoutingTransport: HTTPTransport {
    private let routes: [String: (Int, Data)]
    private(set) var requestedURLs: [URL] = []

    init(routes: [String: (Int, Data)]) {
        self.routes = routes
    }

    init(fixtures: [String: String]) throws {
        self.routes = try fixtures.reduce(into: [:]) { result, fixture in
            result[fixture.key] = (200, try FixtureLoader.data(named: fixture.value))
        }
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url, let route = routes[url.path] else {
            throw URLError(.badURL)
        }
        requestedURLs = requestedURLs + [url]
        let response = HTTPURLResponse(
            url: url,
            statusCode: route.0,
            httpVersion: nil,
            headerFields: nil
        )!
        return (route.1, response)
    }
}
