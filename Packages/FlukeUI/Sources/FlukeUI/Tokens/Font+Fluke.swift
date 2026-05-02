import SwiftUI
import CoreText

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

public extension Font {
    /// Hero / display headings. ~48pt regular weight.
    static let flukeDisplayLarge = Font.custom("Fraunces", size: 44).weight(.medium)

    /// Section headings inside cards / detail views. ~28pt.
    static let flukeDisplayMedium = Font.custom("Fraunces", size: 28).weight(.medium)

    /// Card titles, sheet titles. ~20pt.
    static let flukeDisplaySmall = Font.custom("Fraunces", size: 20).weight(.medium)

    /// Body copy — uses SF Pro Text (system) so iOS Dynamic Type works for free.
    static let flukeBody = Font.system(.body)

    /// Small UI labels — uppercase tracking-wide, system mono.
    static let flukeLabel = Font.system(.caption2, design: .monospaced).weight(.medium)
}
