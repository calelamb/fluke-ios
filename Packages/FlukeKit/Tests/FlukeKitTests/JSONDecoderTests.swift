import XCTest
@testable import FlukeKit

final class JSONDecoderTests: XCTestCase {

    func test_whale_decodesFromAPIShape() throws {
        let whales = try JSONDecoder.fluke.decode(
            [Whale].self,
            from: FixtureLoader.data(named: "whales")
        )
        let whale = try XCTUnwrap(whales.first)

        XCTAssertEqual(whale.id, "fixture-whale-alpha")
        XCTAssertEqual(whale.catalogId, "FX-001")
        XCTAssertEqual(whale.name, "Fixture Whale Alpha")
        XCTAssertEqual(whale.ecotype, .unknown)
        XCTAssertEqual(whale.pod, "FIXTURE_POD")
    }

    func test_sighting_decodesCanonicalPublicShape() throws {
        let sightings = try JSONDecoder.fluke.decode(
            [Sighting].self,
            from: FixtureLoader.data(named: "sightings")
        )
        let sighting = try XCTUnwrap(sightings.first)

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
