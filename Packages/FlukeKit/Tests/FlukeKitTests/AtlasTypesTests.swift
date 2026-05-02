import XCTest
@testable import FlukeKit

final class AtlasTypesTests: XCTestCase {

    func test_pod_displayName() {
        XCTAssertEqual(Pod.j.displayName, "J pod")
        XCTAssertEqual(Pod.biggs.displayName, "Bigg's")
    }

    func test_historicalSighting_decodesFromAPIShape() throws {
        let json = """
        {
          "id": "si_1",
          "observedAt": "2026-04-20T17:45:00.000Z",
          "latitude": 48.5163,
          "longitude": -123.1552,
          "locationName": "Lime Kiln Point",
          "ecotypeGuess": "RESIDENT",
          "whaleIds": ["wh_a", "wh_b"]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder.fluke.decode(HistoricalSighting.self, from: json)
        XCTAssertEqual(decoded.id, "si_1")
        XCTAssertEqual(decoded.locationName, "Lime Kiln Point")
        XCTAssertEqual(decoded.whaleIds, ["wh_a", "wh_b"])
    }
}
