import Foundation
import Testing
@testable import FlukeKit

@Suite("Standalone API contract fixtures")
struct ContractFixtureTests {
    @Test("Missing packaged fixtures fail closed with a clear error")
    func missingPackagedFixtureFailsClosed() {
        #expect(
            throws: FixtureLoadingError.missingResource(name: "missing-contract")
        ) {
            try FixtureLoader.data(named: "missing-contract")
        }
    }

    @Test("Health decodes the released readiness shape")
    func healthDecodes() throws {
        let health = try JSONDecoder.fluke.decode(
            HealthResponse.self,
            from: FixtureLoader.data(named: "health")
        )

        #expect(health.status == .ok)
        #expect(health.timestamp.timeIntervalSince1970 > 0)
    }

    @Test("Capabilities decode the released feature flags")
    func capabilitiesDecode() throws {
        let capabilities = try JSONDecoder.fluke.decode(
            Capabilities.self,
            from: FixtureLoader.data(named: "capabilities")
        )

        #expect(!capabilities.accounts)
        #expect(!capabilities.identification)
        #expect(!capabilities.submissions)
    }

    @Test("Whale catalog decodes the released public shape")
    func whaleCatalogDecodes() throws {
        let response = try JSONDecoder.fluke.decode(
            PaginatedResponse<Whale>.self,
            from: FixtureLoader.data(named: "whales")
        )

        let whales = response.items
        #expect(whales.count == 1)
        #expect(whales[0].catalogId == "FX-001")
        #expect(whales[0].sex == .female)
        #expect(whales[0].deathYear == nil)
        #expect(whales[0].notableEvents[0].type == .milestone)
        #expect(!response.page.hasMore)
        #expect(response.page.nextCursor == nil)
    }

    @Test("Whale detail decodes released relationships and recent sightings")
    func whaleDetailDecodes() throws {
        let whale = try JSONDecoder.fluke.decode(
            WhaleProfile.self,
            from: FixtureLoader.data(named: "whale-detail")
        )

        #expect(whale.mother?.catalogId == "FX-000")
        #expect(whale.offspring.map(\.catalogId) == ["FX-002"])
        #expect(whale.recentSightings[0].locationName == "Fixture Strait")
    }

    @Test("Sightings decode the released public shape")
    func publicSightingsDecode() throws {
        let response = try JSONDecoder.fluke.decode(
            PaginatedResponse<Sighting>.self,
            from: FixtureLoader.data(named: "sightings")
        )

        let sightings = response.items
        #expect(sightings.count == 1)
        #expect(sightings[0].id == "fixture-sighting-1")
        #expect(sightings[0].photos[0].orderIndex == 0)
        #expect(sightings[0].identifiedWhales[0].confidence == .confirmed)
    }

    @Test("External sightings decode the released source shape")
    func externalSightingsDecode() throws {
        let response = try JSONDecoder.fluke.decode(
            PaginatedResponse<ExternalSighting>.self,
            from: FixtureLoader.data(named: "external-sightings")
        )

        let sightings = response.items
        #expect(sightings[0].source == "fixture-feed")
        #expect(sightings[0].trusted)
        #expect(sightings[0].sourceURL == "https://fixtures.invalid/observations/1")
    }

    @Test("Historical sightings decode the released atlas shape")
    func historicalSightingsDecode() throws {
        let response = try JSONDecoder.fluke.decode(
            PaginatedResponse<HistoricalSighting>.self,
            from: FixtureLoader.data(named: "historical-sightings")
        )

        let sightings = response.items
        #expect(sightings[0].whaleIds == ["fixture-whale-alpha"])
    }

    @Test("Whale tracks decode released identity metadata and points")
    func whaleTrackDecodes() throws {
        let track = try JSONDecoder.fluke.decode(
            WhaleTrack.self,
            from: FixtureLoader.data(named: "whale-track")
        )

        #expect(track.whaleId == "fixture-whale-alpha")
        #expect(track.catalogId == "FX-001")
        #expect(track.points[0].id == "fixture-sighting-1")
    }

    @Test("Prediction decodes the released atlas shape")
    func predictionDecodes() throws {
        let prediction = try JSONDecoder.fluke.decode(
            Prediction.self,
            from: FixtureLoader.data(named: "prediction")
        )

        #expect(prediction.modelVersion == "fixture-prediction-v1")
        #expect(prediction.cells[0].probability == 0.72)
    }

    @Test("Identification decodes released ranking metadata")
    func identifyDecodes() throws {
        let response = try JSONDecoder.fluke.decode(
            IdentifyResponse.self,
            from: FixtureLoader.data(named: "identify")
        )

        #expect(response.confidenceBand == .high)
        #expect(response.matches[0].rank == 1)
        #expect(response.uploadURL == "https://fixtures.invalid/identify/upload-1.jpg")
    }

    @Test("Safe errors decode without exposing internal details")
    func safeErrorDecodes() throws {
        let response = try JSONDecoder.fluke.decode(
            SafeError.self,
            from: FixtureLoader.data(named: "safe-error")
        )

        #expect(response.code == "NOT_FOUND")
        #expect(response.message == "Requested fixture resource was not found.")
        #expect(response.requestId == "fixture-request-1")
        #expect(!response.retryable)
    }
}
