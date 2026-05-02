import SwiftUI

public extension Color {
    /// Off-white surface; primary card / content background.
    /// Web token: `--color-bone` `#FAFBFC`.
    static let bone = Color(hex: 0xFAFBFC)

    /// Page background; the lightest semantic surface.
    /// Web token: `--color-fog` `#E8EEF1`.
    static let fog = Color(hex: 0xE8EEF1)

    /// Subtle borders, divider lines, low-contrast type.
    /// Web token: `--color-mist` `#B3C0C8`.
    static let mist = Color(hex: 0xB3C0C8)

    /// Brand accent for active state, links, primary affordance hover.
    /// Web token: `--color-tide` `#2E5972`.
    static let tide = Color(hex: 0x2E5972)

    /// Body text on light surfaces; "the deep ocean blue."
    /// Web token: `--color-deep` `#4A6478`.
    static let deep = Color(hex: 0x4A6478)

    /// Display text + primary CTAs; the deepest dark.
    /// Web token: `--color-abyss` `#0A1F2E`.
    static let abyss = Color(hex: 0x0A1F2E)

    /// Warm accent — used sparingly for status dots, the BIGGS ecotype, ember moments.
    /// Web token: `--color-ember` `#C65A3F`.
    static let ember = Color(hex: 0xC65A3F)
}

public extension Color {
    /// Initialize a Color from a 24-bit hex value (0xRRGGBB).
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}
