import Foundation
import Testing

@testable import FlukeKit

@Suite("Public browse response validation")
struct PublicBrowseValidatorTests {
    @Test("Whales reject non-HTTP image URLs")
    func rejectsUnsafeWhaleURL() {
        let whale = Whale(
            id: "whale-1", catalogId: "J35", name: "Tahlequah", ecotype: .resident,
            pod: "J", sex: .female, birthYear: 1998, deathYear: nil, status: .alive,
            biography: nil, distinguishingMarks: nil, heroImageUrl: "file:///secret",
            notableEvents: [], sourceCitations: []
        )

        #expect(throws: APIError.malformedResponse) {
            try PublicBrowseValidator.whales([whale])
        }
    }

    @Test("Sightings reject out-of-range coordinates")
    func rejectsSightingCoordinates() {
        let sighting = Sighting(
            id: "sighting-1", observedAt: Date(), latitude: 91, longitude: -123,
            locationName: nil, ecotypeGuess: nil, groupSize: nil, behaviorNotes: nil,
            status: .approved, photoUrls: [], photos: [], identifiedWhales: []
        )

        #expect(throws: APIError.malformedResponse) {
            try PublicBrowseValidator.sightings([sighting])
        }
    }

    @Test("Historical sightings reject empty whale IDs")
    func rejectsHistoricalWhaleID() {
        let sighting = HistoricalSighting(
            id: "history-1", observedAt: Date(), latitude: 48, longitude: -123,
            locationName: nil, ecotypeGuess: nil, whaleIds: [""]
        )

        #expect(throws: APIError.malformedResponse) {
            try PublicBrowseValidator.historicalSightings([sighting])
        }
    }

    @Test("Stable identifiers reject whitespace-only values")
    func rejectsBlankStableID() {
        let sighting = HistoricalSighting(
            id: "   ", observedAt: Date(), latitude: 48, longitude: -123,
            locationName: nil, ecotypeGuess: nil, whaleIds: []
        )

        #expect(throws: APIError.malformedResponse) {
            try PublicBrowseValidator.historicalSightings([sighting])
        }
    }

    @Test("Decoded identifiers and text reject control characters")
    func rejectsControlCharacters() {
        let whale = Whale(
            id: "whale-\u{0000}1", catalogId: "J35", name: "Tahlequah\u{0007}",
            ecotype: .resident, pod: "J", sex: .female, birthYear: 1998,
            deathYear: nil, status: .alive, biography: nil, distinguishingMarks: nil,
            heroImageUrl: nil, notableEvents: [], sourceCitations: []
        )

        #expect(throws: APIError.malformedResponse) {
            try PublicBrowseValidator.whales([whale])
        }
    }

    @Test("Predictions reject probabilities outside zero through one")
    func rejectsPredictionProbability() {
        let prediction = Prediction(
            cells: [PredictionCell(lat: 48, lng: -123, probability: 1.1)],
            confidence: 0.8,
            modelVersion: "markov-v1",
            computedAt: Date()
        )

        #expect(throws: APIError.malformedResponse) {
            try PublicBrowseValidator.prediction(prediction)
        }
    }

    @Test("Sightings reject impossible groups and unbounded nested arrays")
    func rejectsLogicalAndArrayBounds() {
        let sighting = Sighting(
            id: "sighting-1", observedAt: Date(), latitude: 48, longitude: -123,
            locationName: "Salish Sea", ecotypeGuess: nil, groupSize: 0,
            behaviorNotes: nil, status: .approved,
            photoUrls: Array(repeating: "https://images.fluke.app/one.jpg", count: 101),
            photos: [], identifiedWhales: []
        )

        #expect(throws: APIError.malformedResponse) {
            try PublicBrowseValidator.sightings([sighting])
        }
    }

    @Test("Whales reject contradictory lifespan fields and oversized text")
    func rejectsWhaleLogicalFields() {
        let whale = Whale(
            id: "whale-1", catalogId: "J35", name: String(repeating: "n", count: 501),
            ecotype: .resident, pod: "J", sex: .female, birthYear: 2000,
            deathYear: 1999, status: .alive, biography: nil, distinguishingMarks: nil,
            heroImageUrl: nil, notableEvents: [], sourceCitations: []
        )

        #expect(throws: APIError.malformedResponse) {
            try PublicBrowseValidator.whales([whale])
        }
    }

    @Test("Canonical fixtures pass validation")
    func canonicalFixturesPass() throws {
        let whales = try JSONDecoder.fluke.decode(
            PaginatedResponse<Whale>.self,
            from: FixtureLoader.data(named: "whales")
        ).items
        let sightings = try JSONDecoder.fluke.decode(
            PaginatedResponse<Sighting>.self,
            from: FixtureLoader.data(named: "sightings")
        ).items
        let prediction = try JSONDecoder.fluke.decode(
            Prediction.self,
            from: FixtureLoader.data(named: "prediction")
        )

        try PublicBrowseValidator.whales(whales)
        try PublicBrowseValidator.sightings(sightings)
        try PublicBrowseValidator.prediction(prediction)
    }
}
