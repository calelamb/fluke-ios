import Foundation
import XCTest
@testable import FlukeUI

final class FlukeUIVersionTests: XCTestCase {
    func test_versionIsExposed() {
        XCTAssertEqual(FlukeUIVersion.current, "0.1.0")
    }

    func test_snapshotBaselinesSelectThePinnedCIRunnerWithoutWeakeningPrecision() {
        XCTAssertEqual(
            releaseSnapshotName(for: OperatingSystemVersion(majorVersion: 15, minorVersion: 7, patchVersion: 0)),
            "macos-15"
        )
        XCTAssertNil(
            releaseSnapshotName(for: OperatingSystemVersion(majorVersion: 26, minorVersion: 5, patchVersion: 1))
        )
    }
}
