import XCTest
@testable import FlukeKit

final class JSONDecoderTests: XCTestCase {

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
