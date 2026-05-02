import XCTest
@testable import FlukeFeatures

final class FlukeFeaturesVersionTests: XCTestCase {
    func test_versionIsExposed() {
        XCTAssertEqual(FlukeFeaturesVersion.current, "0.1.0")
    }
}
