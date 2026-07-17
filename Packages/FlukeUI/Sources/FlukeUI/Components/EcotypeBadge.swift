import SwiftUI

public struct EcotypeBadge: View {
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
            .background(color.opacity(0.22), in: Capsule())
            .overlay {
                Capsule().stroke(color, lineWidth: 1)
            }
            .accessibilityLabel(label)
    }
}
