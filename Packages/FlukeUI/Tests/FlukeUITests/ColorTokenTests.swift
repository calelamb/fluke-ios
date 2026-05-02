import SwiftUI
import XCTest
@testable import FlukeUI

final class ColorTokenTests: XCTestCase {

    func test_bone_matchesWebHexValue() {
        // Web token: #FAFBFC → R=250 G=251 B=252 → 0.980 / 0.984 / 0.988
        let components = Color.bone.rgbComponents()
        XCTAssertEqual(components.r, 0xFA / 255.0, accuracy: 0.005)
        XCTAssertEqual(components.g, 0xFB / 255.0, accuracy: 0.005)
        XCTAssertEqual(components.b, 0xFC / 255.0, accuracy: 0.005)
    }

    func test_abyss_matchesWebHexValue() {
        // Web token: #0A1F2E
        let components = Color.abyss.rgbComponents()
        XCTAssertEqual(components.r, 0x0A / 255.0, accuracy: 0.005)
        XCTAssertEqual(components.g, 0x1F / 255.0, accuracy: 0.005)
        XCTAssertEqual(components.b, 0x2E / 255.0, accuracy: 0.005)
    }

    func test_ember_matchesWebHexValue() {
        // Web token: #C65A3F
        let components = Color.ember.rgbComponents()
        XCTAssertEqual(components.r, 0xC6 / 255.0, accuracy: 0.005)
        XCTAssertEqual(components.g, 0x5A / 255.0, accuracy: 0.005)
        XCTAssertEqual(components.b, 0x3F / 255.0, accuracy: 0.005)
    }

    func test_tide_matchesWebHexValue() {
        // Web token: #2E5972
        let components = Color.tide.rgbComponents()
        XCTAssertEqual(components.r, 0x2E / 255.0, accuracy: 0.005)
        XCTAssertEqual(components.g, 0x59 / 255.0, accuracy: 0.005)
        XCTAssertEqual(components.b, 0x72 / 255.0, accuracy: 0.005)
    }

    func test_allSemanticTokensAreDistinct() {
        let palette: [Color] = [.bone, .fog, .mist, .tide, .deep, .abyss, .ember]
        let components = palette.map { $0.rgbComponents() }
        for i in 0..<components.count {
            for j in (i + 1)..<components.count {
                let same = abs(components[i].r - components[j].r) < 0.001
                          && abs(components[i].g - components[j].g) < 0.001
                          && abs(components[i].b - components[j].b) < 0.001
                XCTAssertFalse(same, "Tokens at index \(i) and \(j) collide")
            }
        }
    }
}

private extension Color {
    /// Approximate RGB extraction for token test only.
    /// Resolves the Color in the default environment then reads its components.
    func rgbComponents() -> (r: Double, g: Double, b: Double) {
        // Color.resolve(in:) is iOS 17+; we target iOS 17.
        let resolved = self.resolve(in: EnvironmentValues())
        return (Double(resolved.red), Double(resolved.green), Double(resolved.blue))
    }
}
