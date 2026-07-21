import SwiftUI

public extension Color {
    /// Off-white surface; primary card / content background.
    /// Web token: `--color-bone` `#F4F0E8`.
    static let bone = Color(hex: 0xF4F0E8)

    /// Page background; the lightest semantic surface.
    /// Web token: `--color-fog` `#E8EEF1`.
    static let fog = Color(hex: 0xE8EEF1)

    /// Subtle borders, divider lines, low-contrast type.
    /// Web token: `--color-mist` `#A8C5D1`.
    static let mist = Color(hex: 0xA8C5D1)

    /// Brand accent for active state, links, primary affordance hover.
    /// Web token: `--color-tide` `#2C6E8F`.
    static let tide = Color(hex: 0x2C6E8F)

    /// Body text on light surfaces; "the deep ocean blue."
    /// Web token: `--color-deep` `#143B52`.
    static let deep = Color(hex: 0x143B52)

    /// Display text + primary CTAs; the deepest dark.
    /// Web token: `--color-abyss` `#0A1F2E`.
    static let abyss = Color(hex: 0x0A1F2E)

    /// Warm accent — used sparingly for status dots, the BIGGS ecotype, ember moments.
    /// Web token: `--color-ember` `#D97742`.
    static let ember = Color(hex: 0xD97742)

    /// Midtone between `tide` and `deep` — used for L pod's polyline in Atlas.
    /// Web token: `--color-swell` `#3B5F75`.
    static let swell = Color(hex: 0x3B5F75)
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
