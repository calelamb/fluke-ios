import SwiftUI
import FlukeUI

public struct IdentifyPlaceholder: View {
    public init() {}
    public var body: some View {
        PlaceholderScreen(
            title: "Identify",
            subtitle: "Photograph a dorsal fin and get top-three matches from the catalog.",
            comingIn: "Coming in M-iOS-6"
        )
    }
}
