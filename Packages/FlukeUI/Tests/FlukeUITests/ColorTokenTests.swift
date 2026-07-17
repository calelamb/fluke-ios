import SwiftUI
import XCTest
@testable import FlukeUI

final class ColorTokenTests: XCTestCase {

    func test_fog_matchesWebHexValue() {
        assertColor(.fog, equals: 0xE8EEF1)
    }

    func test_bone_matchesWebHexValue() {
        // Web token: #F4F0E8
        let components = Color.bone.rgbComponents()
        XCTAssertEqual(components.r, 0xF4 / 255.0, accuracy: 0.005)
        XCTAssertEqual(components.g, 0xF0 / 255.0, accuracy: 0.005)
        XCTAssertEqual(components.b, 0xE8 / 255.0, accuracy: 0.005)
    }

    func test_abyss_matchesWebHexValue() {
        assertColor(.abyss, equals: 0x0A1F2E)
    }

    func test_mist_matchesWebHexValue() {
        assertColor(.mist, equals: 0xA8C5D1)
    }

    func test_deep_matchesWebHexValue() {
        assertColor(.deep, equals: 0x143B52)
    }

    func test_ember_matchesWebHexValue() {
        // Web token: #D97742
        let components = Color.ember.rgbComponents()
        XCTAssertEqual(components.r, 0xD9 / 255.0, accuracy: 0.005)
        XCTAssertEqual(components.g, 0x77 / 255.0, accuracy: 0.005)
        XCTAssertEqual(components.b, 0x42 / 255.0, accuracy: 0.005)
    }

    func test_tide_matchesWebHexValue() {
        // Web token: #2C6E8F
        let components = Color.tide.rgbComponents()
        XCTAssertEqual(components.r, 0x2C / 255.0, accuracy: 0.005)
        XCTAssertEqual(components.g, 0x6E / 255.0, accuracy: 0.005)
        XCTAssertEqual(components.b, 0x8F / 255.0, accuracy: 0.005)
    }

    func test_swell_matchesWebHexValue() {
        // Web token: #3B5F75 — midtone between tide (#2E5972) and deep (#4A6478)
        let components = Color.swell.rgbComponents()
        XCTAssertEqual(components.r, 0x3B / 255.0, accuracy: 0.005)
        XCTAssertEqual(components.g, 0x5F / 255.0, accuracy: 0.005)
        XCTAssertEqual(components.b, 0x75 / 255.0, accuracy: 0.005)
    }

    private func assertColor(
        _ color: Color,
        equals hex: UInt32,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let components = color.rgbComponents()
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        XCTAssertEqual(components.r, red, accuracy: 0.005, file: file, line: line)
        XCTAssertEqual(components.g, green, accuracy: 0.005, file: file, line: line)
        XCTAssertEqual(components.b, blue, accuracy: 0.005, file: file, line: line)
    }

    func test_allSemanticTokensAreDistinct() {
        let palette: [Color] = [.bone, .fog, .mist, .tide, .deep, .abyss, .ember, .swell]
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
