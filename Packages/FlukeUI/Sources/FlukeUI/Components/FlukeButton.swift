import SwiftUI

public enum FlukeButtonKind: Sendable {
    case primary
    case secondary
}

public struct FlukeButtonStyle: ButtonStyle, Sendable {
    public static let primary = FlukeButtonStyle(kind: .primary)
    public static let secondary = FlukeButtonStyle(kind: .secondary)

    public let kind: FlukeButtonKind

    public init(kind: FlukeButtonKind) {
        self.kind = kind
    }

    public func makeBody(configuration: Configuration) -> some View {
        FlukeButtonLabel(
            configuration: configuration,
            kind: kind
        )
    }
}

private struct FlukeButtonLabel: View {
    @Environment(\.isEnabled) private var isEnabled

    let configuration: FlukeButtonStyle.Configuration
    let kind: FlukeButtonKind

    var body: some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 16)
            .background(background)
            .contentShape(Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.48)
    }

    private var foregroundColor: Color {
        switch kind {
        case .primary: .bone
        case .secondary: .tide
        }
    }

    @ViewBuilder
    private var background: some View {
        switch kind {
        case .primary:
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.tide)
        case .secondary:
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.bone)
                .stroke(Color.tide, lineWidth: 1)
        }
    }
}
