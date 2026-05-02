import XCTest
@testable import FlukeKit

final class SalishSeaProjectionTests: XCTestCase {

    private let projection = SalishSeaProjection.salishSea

    func test_projects_southwestCorner_toOrigin() {
        let p = projection.project(lat: 47.0, lng: -124.7)
        XCTAssertEqual(p.x, 0.0, accuracy: 0.001)
        XCTAssertEqual(p.y, 1.0, accuracy: 0.001) // south = bottom = y=1 (image coords)
    }

    func test_projects_northeastCorner_toUnit() {
        let p = projection.project(lat: 49.5, lng: -122.0)
        XCTAssertEqual(p.x, 1.0, accuracy: 0.001)
        XCTAssertEqual(p.y, 0.0, accuracy: 0.001)
    }

    func test_projects_limeKilnPoint_intoBox() {
        let p = projection.project(lat: 48.516, lng: -123.155)
        // Lime Kiln Point is roughly mid-latitude, west-of-center.
        XCTAssertGreaterThan(p.x, 0.5)
        XCTAssertLessThan(p.x, 0.65)
        XCTAssertGreaterThan(p.y, 0.3)
        XCTAssertLessThan(p.y, 0.5)
    }

    func test_unproject_isInverseOfProject() {
        let original = (lat: 48.55, lng: -123.20)
        let p = projection.project(lat: original.lat, lng: original.lng)
        let back = projection.unproject(x: p.x, y: p.y)
        XCTAssertEqual(back.lat, original.lat, accuracy: 0.001)
        XCTAssertEqual(back.lng, original.lng, accuracy: 0.001)
    }
}
