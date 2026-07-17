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
        for id in ["   ", "\u{FEFF}"] {
            let sighting = HistoricalSighting(
                id: id, observedAt: Date(), latitude: 48, longitude: -123,
                locationName: nil, ecotypeGuess: nil, whaleIds: []
            )

            #expect(throws: APIError.malformedResponse) {
                try PublicBrowseValidator.historicalSightings([sighting])
            }
        }
    }

    @Test("Canonical identifiers, empty text, years, statuses, and nested bounds are accepted")
    func acceptsCanonicalBoundaryValues() throws {
        let maximumID = String(repeating: " ", count: 199) + "x"
        let maximumURL = "https://example.com/" + String(repeating: "x", count: 2_028)
        let whale = Whale(
            id: "whale-\u{0000}1", catalogId: maximumID, name: "", ecotype: .resident,
            pod: "\u{0007}", sex: .female, birthYear: 9_999, deathYear: 1_000,
            status: .alive, biography: String(repeating: "b", count: 20_000),
            distinguishingMarks: "", heroImageUrl: maximumURL,
            notableEvents: [NotableEvent(
                year: 1_000, date: "", type: .milestone, summary: "", source: ""
            )],
            sourceCitations: [SourceCitation(label: "", url: "http://example.com/source")]
        )
        let sighting = makeSighting(
            groupSize: 200,
            behaviorNotes: "\u{0000}",
            status: .pending,
            photoUrls: Array(repeating: "http://example.com/photo", count: 1_000),
            photos: [SightingPhoto(
                id: "photo-1",
                url: "http://example.com/photo",
                thumbnailUrl: "https://example.com/thumb",
                orderIndex: -1
            )]
        )

        try PublicBrowseValidator.whales([whale])
        try PublicBrowseValidator.sightings([sighting])
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

    @Test("Sightings reject group sizes and nested arrays above canonical bounds")
    func rejectsCanonicalSightingBounds() {
        let invalidSightings = [
            makeSighting(groupSize: 0),
            makeSighting(groupSize: 201),
            makeSighting(
                photoUrls: Array(repeating: "https://images.fluke.app/one.jpg", count: 1_001)
            ),
        ]

        for sighting in invalidSightings {
            #expect(throws: APIError.malformedResponse) {
                try PublicBrowseValidator.sightings([sighting])
            }
        }
    }

    @Test("Canonical string, year, and URL maximums are enforced")
    func rejectsCanonicalScalarBounds() {
        let oversizedID = String(repeating: " ", count: 200) + "x"
        let oversizedURL = "https://example.com/" + String(repeating: "x", count: 2_049)
        let oversizedText = String(repeating: "n", count: 20_001)
        let oversizedUnicodeID = String(repeating: "🐋", count: 101)
        let oversizedUnicodeText = String(repeating: "🐋", count: 10_001)
        let oversizedUnicodeURL = "https://example.com/" + String(repeating: "🐋", count: 1_015)
        let invalidWhales = [
            makeWhale(id: oversizedID),
            makeWhale(id: oversizedUnicodeID),
            makeWhale(name: oversizedText),
            makeWhale(name: oversizedUnicodeText),
            makeWhale(birthYear: 999),
            makeWhale(heroImageUrl: oversizedURL),
            makeWhale(heroImageUrl: oversizedUnicodeURL),
        ]

        for whale in invalidWhales {
            #expect(throws: APIError.malformedResponse) {
                try PublicBrowseValidator.whales([whale])
            }
        }
    }

    @Test("Track and prediction collections cap at one thousand items")
    func rejectsOversizedTrackAndPrediction() {
        let points = Array(repeating: MovementTrackPoint(
            id: "point-1", observedAt: Date(), latitude: 48, longitude: -123,
            locationName: nil, behaviorNotes: nil
        ), count: 1_001)
        let prediction = Prediction(
            cells: Array(repeating: PredictionCell(lat: 48, lng: -123, probability: 0.5), count: 1_001),
            confidence: 0.8,
            modelVersion: "model",
            computedAt: Date()
        )

        #expect(throws: APIError.malformedResponse) {
            try PublicBrowseValidator.track(points)
        }
        #expect(throws: APIError.malformedResponse) {
            try PublicBrowseValidator.prediction(prediction)
        }
    }

    @Test("Track and prediction collections accept exactly one thousand items")
    func acceptsMaximumTrackAndPrediction() throws {
        let points = Array(repeating: MovementTrackPoint(
            id: "point-1", observedAt: Date(), latitude: 48, longitude: -123,
            locationName: "", behaviorNotes: ""
        ), count: 1_000)
        let prediction = Prediction(
            cells: Array(repeating: PredictionCell(lat: 48, lng: -123, probability: 0.5), count: 1_000),
            confidence: 0.8,
            modelVersion: "",
            computedAt: Date()
        )

        try PublicBrowseValidator.track(points)
        try PublicBrowseValidator.prediction(prediction)
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

    private func makeWhale(
        id: String = "whale-1",
        name: String? = "Tahlequah",
        birthYear: Int? = 1998,
        heroImageUrl: String? = nil
    ) -> Whale {
        Whale(
            id: id, catalogId: "J35", name: name, ecotype: .resident,
            pod: "J", sex: .female, birthYear: birthYear, deathYear: nil,
            status: .alive, biography: nil, distinguishingMarks: nil,
            heroImageUrl: heroImageUrl, notableEvents: [], sourceCitations: []
        )
    }

    private func makeSighting(
        groupSize: Int? = 4,
        behaviorNotes: String? = nil,
        status: SightingStatus = .approved,
        photoUrls: [String] = [],
        photos: [SightingPhoto] = []
    ) -> Sighting {
        Sighting(
            id: "sighting-1", observedAt: Date(), latitude: 48, longitude: -123,
            locationName: "Salish Sea", ecotypeGuess: nil, groupSize: groupSize,
            behaviorNotes: behaviorNotes, status: status, photoUrls: photoUrls,
            photos: photos, identifiedWhales: []
        )
    }
}
