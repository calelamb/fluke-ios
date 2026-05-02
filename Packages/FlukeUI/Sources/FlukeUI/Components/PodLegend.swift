import SwiftUI

public struct PodLegend: View {

    public struct Entry: Identifiable {
        public let id = UUID()
        public let label: String
        public let count: Int
        public let color: Color
        public init(label: String, count: Int, color: Color) {
            self.label = label
            self.count = count
            self.color = color
        }
    }

    public let entries: [Entry]

    public init(entries: [Entry]) {
        self.entries = entries
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(entries) { entry in
                HStack(spacing: 8) {
                    Capsule()
                        .fill(entry.color)
                        .frame(width: 14, height: 3)
                    Text("\(entry.label) · \(entry.count)")
                        .font(.system(.caption2, design: .monospaced).weight(.medium))
                        .foregroundStyle(Color.abyss)
                }
            }
        }
        .padding(8)
        .background(Color.bone.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6).stroke(Color.mist.opacity(0.5), lineWidth: 0.5)
        )
    }
}
