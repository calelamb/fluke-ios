import XCTest
@testable import FlukeKit

final class FlukeKitVersionTests: XCTestCase {
    func test_versionIsExposed() {
        XCTAssertEqual(FlukeKitVersion.current, "0.1.0")
    }
}
