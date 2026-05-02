import XCTest
@testable import FlukeKit

final class JSONDecoderTests: XCTestCase {

    func test_whale_decodesFromAPIShape() throws {
        let json = """
        {
          "id": "wh_abc",
          "catalogId": "J35",
          "name": "Tahlequah",
          "ecotype": "RESIDENT",
          "pod": "J",
          "biography": "A southern resident orca.",
          "heroImageUrl": null,
          "createdAt": "2026-01-15T18:00:00.000Z",
          "updatedAt": "2026-01-15T18:00:00.000Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder.fluke
        let whale = try decoder.decode(Whale.self, from: json)

        XCTAssertEqual(whale.id, "wh_abc")
        XCTAssertEqual(whale.catalogId, "J35")
        XCTAssertEqual(whale.name, "Tahlequah")
        XCTAssertEqual(whale.ecotype, .resident)
        XCTAssertEqual(whale.pod, "J")
    }

    func test_sighting_decodesISO8601DateAndDecimalCoords() throws {
        let json = """
        {
          "id": "si_xyz",
          "observedAt": "2026-04-20T17:45:00.000Z",
          "latitude": "48.516300",
          "longitude": "-123.155200",
          "locationName": "Lime Kiln Point",
          "ecotypeGuess": "RESIDENT",
          "groupSize": 5,
          "behaviorNotes": "Fast travel south",
          "observerEmail": "anon@example.com",
          "status": "APPROVED",
          "createdAt": "2026-04-20T18:00:00.000Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder.fluke
        let sighting = try decoder.decode(Sighting.self, from: json)

        XCTAssertEqual(sighting.id, "si_xyz")
        XCTAssertEqual(sighting.locationName, "Lime Kiln Point")
        XCTAssertEqual(sighting.ecotypeGuess, .resident)
        XCTAssertEqual(sighting.groupSize, 5)
        XCTAssertEqual(sighting.status, .approved)
        XCTAssertEqual(sighting.latitude, 48.5163, accuracy: 0.0001)
        XCTAssertEqual(sighting.longitude, -123.1552, accuracy: 0.0001)
    }

    func test_ecotype_unknownStringFallsBackToUnknown() throws {
        let json = #"{"ecotype":"MARTIAN"}"#.data(using: .utf8)!
        struct Wrapper: Decodable { let ecotype: Ecotype }
        let wrapped = try JSONDecoder.fluke.decode(Wrapper.self, from: json)
        XCTAssertEqual(wrapped.ecotype, .unknown)
    }
}
