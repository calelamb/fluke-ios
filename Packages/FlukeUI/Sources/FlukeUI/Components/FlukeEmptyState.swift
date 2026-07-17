import SwiftUI

public struct FlukeEmptyState: View {
    @Environment(\.flukeContrast) private var contrast

    public let title: String
    public let message: String

    public init(title: String, message: String) {
        self.title = title
        self.message = message
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.bone)

            VStack(spacing: 12) {
                DorsalFinShape()
                    .fill(Color.tide)
                    .frame(width: 48, height: 48)
                    .accessibilityHidden(true)

                EditorialHeading(level: .card, text: title)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.flukeBody)
                    .foregroundStyle(Color.deep)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    contrast == .increased ? Color.deep : Color.mist,
                    lineWidth: contrast == .increased ? 2 : 1
                )
        }
    }
}
