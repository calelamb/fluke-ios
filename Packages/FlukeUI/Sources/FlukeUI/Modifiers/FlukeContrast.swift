import SwiftUI

public enum FlukeContrast: Sendable {
    case standard
    case increased
}

private struct FlukeContrastKey: EnvironmentKey {
    static let defaultValue = FlukeContrast.standard
}

extension EnvironmentValues {
    var flukeContrast: FlukeContrast {
        get { self[FlukeContrastKey.self] }
        set { self[FlukeContrastKey.self] = newValue }
    }
}

public extension View {
    /// Injects a deterministic contrast presentation, including for previews and tests.
    func flukeContrast(_ contrast: FlukeContrast) -> some View {
        environment(\.flukeContrast, contrast)
    }

    /// Maps the platform accessibility contrast setting into Fluke's presentation seam.
    func flukeSystemContrast() -> some View {
        modifier(FlukeSystemContrastModifier())
    }
}

private struct FlukeSystemContrastModifier: ViewModifier {
    @Environment(\.colorSchemeContrast) private var systemContrast

    func body(content: Content) -> some View {
        content.flukeContrast(systemContrast == .increased ? .increased : .standard)
    }
}
