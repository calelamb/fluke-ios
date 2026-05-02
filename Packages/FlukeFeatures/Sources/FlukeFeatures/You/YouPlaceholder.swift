import SwiftUI
import FlukeUI

public struct YouPlaceholder: View {
    public init() {}
    public var body: some View {
        PlaceholderScreen(
            title: "You",
            subtitle: "Sign in with Apple to save your sightings and see your contributions.",
            comingIn: "Coming in M-iOS-3"
        )
    }
}
