import XCTest
@testable import FlukeUI

final class FlukeUIVersionTests: XCTestCase {
    func test_versionIsExposed() {
        XCTAssertEqual(FlukeUIVersion.current, "0.1.0")
    }
}
