import SwiftUI

/// Wider, atlas-context scrubber. Decades visually marked along the track.
public struct DateScrubberAtlas: View {

    @Binding public var date: Date
    public let range: ClosedRange<Date>

    public init(date: Binding<Date>, range: ClosedRange<Date>) {
        self._date = date
        self.range = range
    }

    public var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(formatYear(range.lowerBound))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color.deep)
                Spacer()
                Text(formattedFull(date))
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundStyle(Color.abyss)
                Spacer()
                Text(formatYear(range.upperBound))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color.deep)
            }
            Slider(
                value: Binding(
                    get: { date.timeIntervalSince(range.lowerBound) },
                    set: { date = range.lowerBound.addingTimeInterval($0) }
                ),
                in: 0...range.upperBound.timeIntervalSince(range.lowerBound)
            )
            .tint(Color.tide)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.bone.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: Color.abyss.opacity(0.1), radius: 6, y: 2)
    }

    private func formatYear(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        return f.string(from: d)
    }

    private func formattedFull(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        return f.string(from: d)
    }
}
