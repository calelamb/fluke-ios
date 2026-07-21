import SwiftUI

public struct EcotypeBadge: View {
    @Environment(\.flukeContrast) private var contrast

    public let label: String
    public let color: Color

    public init(label: String, color: Color) {
        self.label = label
        self.color = color
    }

    public var body: some View {
        Text(label.uppercased())
            .font(.flukeLabel)
            .foregroundStyle(Color.abyss)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(contrast == .increased ? 0.38 : 0.22), in: Capsule())
            .overlay {
                Capsule().stroke(
                    contrast == .increased ? Color.abyss : color,
                    lineWidth: contrast == .increased ? 2 : 1
                )
            }
            .accessibilityLabel(label)
    }
}
