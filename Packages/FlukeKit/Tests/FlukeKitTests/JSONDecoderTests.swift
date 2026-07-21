import XCTest
@testable import FlukeKit

final class JSONDecoderTests: XCTestCase {

    private struct TimestampEnvelope: Codable, Sendable {
        let timestamp: Date
    }

    func test_flukeDecoder_returnsIndependentInstances() {
        XCTAssertFalse(JSONDecoder.fluke === JSONDecoder.fluke)
    }

    func test_flukeDecoder_mutatingOneInstanceDoesNotAffectTheNext() throws {
        let mutated = JSONDecoder.fluke
        mutated.dateDecodingStrategy = .secondsSince1970
        let json = Data(#"{"timestamp":"2026-07-19T12:34:56Z"}"#.utf8)

        XCTAssertThrowsError(try mutated.decode(TimestampEnvelope.self, from: json))
        XCTAssertNoThrow(try JSONDecoder.fluke.decode(TimestampEnvelope.self, from: json))
    }

    func test_flukeDecoder_decodesFractionalISO8601Exactly() throws {
        let json = Data(#"{"timestamp":"2026-07-19T12:34:56.789Z"}"#.utf8)

        let decoded = try JSONDecoder.fluke.decode(TimestampEnvelope.self, from: json)

        XCTAssertEqual(decoded.timestamp.timeIntervalSince1970, 1_784_464_496.789, accuracy: 0.000_001)
    }

    func test_flukeDecoder_decodesNonFractionalISO8601Exactly() throws {
        let json = Data(#"{"timestamp":"2026-07-19T12:34:56Z"}"#.utf8)

        let decoded = try JSONDecoder.fluke.decode(TimestampEnvelope.self, from: json)

        XCTAssertEqual(decoded.timestamp.timeIntervalSince1970, 1_784_464_496, accuracy: 0.000_001)
    }

    func test_flukeDecoder_truncatesSubmillisecondFractionLikeLegacyFormatter() throws {
        let json = Data(#"{"timestamp":"2026-07-19T12:34:56.123456Z"}"#.utf8)

        let decoded = try JSONDecoder.fluke.decode(TimestampEnvelope.self, from: json)

        XCTAssertEqual(decoded.timestamp.timeIntervalSince1970, 1_784_464_496.123, accuracy: 0.000_001)
    }

    func test_flukeDecoder_rejectsLeapSecondLikeLegacyFormatter() {
        let json = Data(#"{"timestamp":"2016-12-31T23:59:60Z"}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder.fluke.decode(TimestampEnvelope.self, from: json))
    }

    func test_flukeDecoder_decodesPositiveAndNegativeTimezoneOffsets() throws {
        let positiveJSON = Data(#"{"timestamp":"2026-07-19T12:34:56+05:30"}"#.utf8)
        let negativeJSON = Data(#"{"timestamp":"2026-07-19T12:34:56-07:00"}"#.utf8)

        let positive = try JSONDecoder.fluke.decode(TimestampEnvelope.self, from: positiveJSON)
        let negative = try JSONDecoder.fluke.decode(TimestampEnvelope.self, from: negativeJSON)

        XCTAssertEqual(positive.timestamp.timeIntervalSince1970, 1_784_444_696, accuracy: 0.000_001)
        XCTAssertEqual(negative.timestamp.timeIntervalSince1970, 1_784_489_696, accuracy: 0.000_001)
    }

    func test_flukeDecoder_isSafeForConcurrentIndependentDecodes() async throws {
        let fractionalJSON = Data(#"{"timestamp":"2026-07-19T12:34:56.789Z"}"#.utf8)
        let plainJSON = Data(#"{"timestamp":"2026-07-19T12:34:56Z"}"#.utf8)

        let decodedDates = try await withThrowingTaskGroup(of: Date.self) { group in
            for index in 0..<100 {
                let json = index.isMultiple(of: 2) ? fractionalJSON : plainJSON
                group.addTask {
                    try JSONDecoder.fluke.decode(TimestampEnvelope.self, from: json).timestamp
                }
            }

            return try await group.reduce(into: []) { dates, date in
                dates.append(date)
            }
        }

        XCTAssertEqual(decodedDates.count, 100)
        XCTAssertEqual(Set(decodedDates.map(\.timeIntervalSince1970)), [1_784_464_496, 1_784_464_496.789])
    }

    func test_flukeEncoder_emitsFractionalISO8601() throws {
        let value = TimestampEnvelope(timestamp: Date(timeIntervalSince1970: 1_784_464_496.789))

        let encoded = try JSONEncoder.fluke.encode(value)

        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), #"{"timestamp":"2026-07-19T12:34:56.789Z"}"#)
    }

    func test_flukeEncoder_roundsPreEpochFractionLikeLegacyFormatter() throws {
        let value = TimestampEnvelope(timestamp: Date(timeIntervalSince1970: -0.1234))

        let encoded = try JSONEncoder.fluke.encode(value)

        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), #"{"timestamp":"1969-12-31T23:59:59.877Z"}"#)
    }

    func test_whale_decodesFromAPIShape() throws {
        let response = try JSONDecoder.fluke.decode(
            PaginatedResponse<Whale>.self,
            from: FixtureLoader.data(named: "whales")
        )
        let whale = try XCTUnwrap(response.items.first)

        XCTAssertEqual(whale.id, "fixture-whale-alpha")
        XCTAssertEqual(whale.catalogId, "FX-001")
        XCTAssertEqual(whale.name, "Fixture Whale Alpha")
        XCTAssertEqual(whale.ecotype, .unknown)
        XCTAssertEqual(whale.pod, "FIXTURE_POD")
    }

    func test_sighting_decodesCanonicalPublicShape() throws {
        let response = try JSONDecoder.fluke.decode(
            PaginatedResponse<Sighting>.self,
            from: FixtureLoader.data(named: "sightings")
        )
        let sighting = try XCTUnwrap(response.items.first)

        XCTAssertEqual(sighting.id, "fixture-sighting-1")
        XCTAssertEqual(sighting.locationName, "Fixture Strait")
        XCTAssertEqual(sighting.ecotypeGuess, .unknown)
        XCTAssertEqual(sighting.groupSize, 4)
        XCTAssertEqual(sighting.status, .approved)
        XCTAssertEqual(sighting.latitude, 12.345, accuracy: 0.0001)
        XCTAssertEqual(sighting.longitude, -45.678, accuracy: 0.0001)
    }

    func test_ecotype_unknownStringFallsBackToUnknown() throws {
        let json = #"{"ecotype":"MARTIAN"}"#.data(using: .utf8)!
        struct Wrapper: Decodable { let ecotype: Ecotype }
        let wrapped = try JSONDecoder.fluke.decode(Wrapper.self, from: json)
        XCTAssertEqual(wrapped.ecotype, .unknown)
    }
}
