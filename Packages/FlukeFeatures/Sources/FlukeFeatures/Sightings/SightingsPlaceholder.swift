import SwiftUI
import FlukeUI

public struct SightingsPlaceholder: View {
    public init() {}
    public var body: some View {
        PlaceholderScreen(
            title: "Sightings",
            subtitle: "Map of recent approved sightings across the Salish Sea.",
            comingIn: "Coming in M-iOS-2"
        )
    }
}
