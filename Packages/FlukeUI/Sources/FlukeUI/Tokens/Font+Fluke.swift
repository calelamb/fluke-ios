import CoreText
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Registers FlukeUI's bundled fonts with the system. Must be called before
/// any view that references `Font.fluke*` tokens. Safe to call multiple times.
public enum FlukeUIFontRegistration {
    private static var didRegister = false

    public static func registerIfNeeded() {
        guard !didRegister else { return }
        didRegister = true
        registerFont(named: "Fraunces-Variable", extension: "ttf")
    }

    private static func registerFont(named name: String, extension ext: String) {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext) else {
            assertionFailure("Missing font resource: \(name).\(ext)")
            return
        }
        var error: Unmanaged<CFError>?
        let registered = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        if !registered {
            // Already registered is not an error worth crashing over.
            let nsError = error?.takeRetainedValue() as Error?
            print("[FlukeUI] Font registration: \(nsError?.localizedDescription ?? "unknown")")
        }
    }
}

public struct FlukeFontDescriptor: Sendable {
    public let size: CGFloat
    public let relativeStyle: Font.TextStyle

    public static let displayLarge = FlukeFontDescriptor(
        size: 44,
        relativeStyle: .largeTitle
    )
    public static let displayMedium = FlukeFontDescriptor(
        size: 28,
        relativeStyle: .title
    )
    public static let displaySmall = FlukeFontDescriptor(
        size: 20,
        relativeStyle: .title3
    )

    public var font: Font {
        Font.custom("Fraunces", size: size, relativeTo: relativeStyle)
            .weight(.medium)
    }
}

public extension Font {
    /// Hero / display headings. ~48pt regular weight.
    static let flukeDisplayLarge = FlukeFontDescriptor.displayLarge.font

    /// Section headings inside cards / detail views. ~28pt.
    static let flukeDisplayMedium = FlukeFontDescriptor.displayMedium.font

    /// Card titles, sheet titles. ~20pt.
    static let flukeDisplaySmall = FlukeFontDescriptor.displaySmall.font

    /// Body copy — uses SF Pro Text (system) so iOS Dynamic Type works for free.
    static let flukeBody = Font.system(.body)

    /// Small UI labels — uppercase tracking-wide, system mono.
    static let flukeLabel = Font.system(.caption2, design: .monospaced).weight(.medium)
}
