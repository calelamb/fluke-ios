import SwiftUI

private struct FlukeMotionModifier: ViewModifier {
    let animation: Animation
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content.transaction { transaction in
            transaction.animation = reduceMotion ? nil : animation
        }
    }
}

public extension View {
    func flukeMotion(
        _ animation: Animation = .flukeBase,
        reduceMotion: Bool
    ) -> some View {
        modifier(
            FlukeMotionModifier(
                animation: animation,
                reduceMotion: reduceMotion
            )
        )
    }
}
