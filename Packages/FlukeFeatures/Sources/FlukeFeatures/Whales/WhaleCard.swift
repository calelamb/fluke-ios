import FlukeKit
import FlukeUI
import SwiftUI

public struct WhaleCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let whale: Whale

    public init(whale: Whale) {
        self.whale = whale
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            hero
                .frame(maxWidth: .infinity)
                .frame(height: 128)
                .clipped()
            Text(whale.name ?? whale.catalogId)
                .font(.flukeDisplaySmall)
                .foregroundStyle(Color.abyss)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            Text(identityLine)
                .font(.flukeLabel)
                .foregroundStyle(Color.deep)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
        }
        .padding(12)
        .background(Color.bone, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(whale.ecotype.flukeColor.opacity(0.38), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var hero: some View {
        if let value = whale.heroImageUrl, let url = URL(string: value) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                case .empty: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failure: finFallback
                @unknown default: finFallback
                }
            }
            .background(Color.fog)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            finFallback
        }
    }

    private var finFallback: some View {
        DorsalFinShape()
            .fill(whale.ecotype.flukeColor.opacity(0.7))
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.fog, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)
    }

    private var identityLine: String {
        [whale.catalogId, whale.pod.map { "Pod \($0)" }, whale.ecotype.flukeDisplayName]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var accessibilityLabel: String {
        "\(whale.name ?? "Unnamed whale"), catalog \(whale.catalogId), \(whale.ecotype.flukeDisplayName)"
    }
}
