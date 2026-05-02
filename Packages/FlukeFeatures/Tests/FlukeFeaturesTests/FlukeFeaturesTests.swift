import SwiftUI
import XCTest
@testable import FlukeFeatures

final class FlukeFeaturesVersionTests: XCTestCase {
    func test_versionIsExposed() {
        XCTAssertEqual(FlukeFeaturesVersion.current, "0.1.0")
    }
}

final class PlaceholderRenderTests: XCTestCase {
    func test_allPlaceholdersInstantiate() {
        // We can't render a SwiftUI view in a unit test cheaply; we just
        // confirm that initializing each one doesn't crash and yields a View.
        _ = SightingsPlaceholder()
        _ = WhalesPlaceholder()
        _ = IdentifyPlaceholder()
        _ = LearnPlaceholder()
        _ = YouPlaceholder()
    }
}
