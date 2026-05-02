import SwiftUI

public struct PlaceholderScreen: View {
    public let title: String
    public let subtitle: String
    public let comingIn: String

    public init(title: String, subtitle: String, comingIn: String) {
        self.title = title
        self.subtitle = subtitle
        self.comingIn = comingIn
    }

    public var body: some View {
        VStack(spacing: 16) {
            DorsalFinShape()
                .fill(Color.tide)
                .frame(width: 56, height: 56)
                .opacity(0.6)
            Text(title)
                .font(.flukeDisplayMedium)
                .foregroundStyle(Color.abyss)
            Text(subtitle)
                .font(.flukeBody)
                .foregroundStyle(Color.deep)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Text(comingIn.uppercased())
                .font(.flukeLabel)
                .foregroundStyle(Color.mist)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.fog)
    }
}

#Preview {
    PlaceholderScreen(
        title: "Sightings",
        subtitle: "The map and detail panels live here.",
        comingIn: "Coming in M-iOS-2"
    )
}
