import SwiftUI

public enum EditorialHeadingLevel: Sendable {
    case hero
    case section
    case card

    fileprivate var font: Font {
        switch self {
        case .hero: .flukeDisplayLarge
        case .section: .flukeDisplayMedium
        case .card: .flukeDisplaySmall
        }
    }
}

public struct EditorialHeading: View {
    public let level: EditorialHeadingLevel
    public let text: String

    public init(level: EditorialHeadingLevel, text: String) {
        self.level = level
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(level.font)
            .foregroundStyle(Color.abyss)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}
