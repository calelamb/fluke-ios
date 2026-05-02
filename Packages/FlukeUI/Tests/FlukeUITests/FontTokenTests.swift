import SwiftUI
import XCTest
@testable import FlukeUI

#if canImport(UIKit)
import UIKit
#endif

final class FontTokenTests: XCTestCase {

    override func setUp() async throws {
        // Force the bundle's font to register before tests run.
        FlukeUIFontRegistration.registerIfNeeded()
    }

    func test_fraunces_isAvailableAfterRegistration() {
        #if canImport(UIKit)
        let font = UIFont(name: "Fraunces", size: 24)
        XCTAssertNotNil(font, "Fraunces variable font is not registered with the system")
        #endif
    }

    func test_displayLargeFont_returnsAFont() {
        let font = Font.flukeDisplayLarge
        // Font is opaque in SwiftUI; we can only verify it doesn't crash.
        // The visual is locked by the snapshot test on the placeholder screen.
        _ = font
    }
}
