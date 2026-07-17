import FlukeReleaseB
import FlukeUI
import SwiftUI

public struct IdentifyResultsView: View {
  public let matches: [IdentifyMatch]
  public let disclaimer: String
  public let feedbackEnabled: Bool

  public init(matches: [IdentifyMatch], disclaimer: String, feedbackEnabled: Bool) {
    self.matches = matches
    self.disclaimer = disclaimer
    self.feedbackEnabled = feedbackEnabled
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      EditorialHeading(level: .section, text: "Possible visual matches")
      ScrollView(.horizontal) {
        LazyHStack(spacing: 12) {
          ForEach(Array(matches.enumerated()), id: \.offset) { index, match in
            matchCard(match, position: index + 1)
          }
        }
        .scrollTargetLayout()
      }
      .scrollTargetBehavior(.viewAligned)
      .accessibilityLabel("Possible visual matches")

      Label(disclaimer, systemImage: "eye.trianglebadge.exclamationmark")
        .font(.callout.weight(.semibold))
        .foregroundStyle(Color.deep)
        .accessibilityAddTraits(.isStaticText)

      Button("Wrong match") {}
        .buttonStyle(FlukeButtonStyle.secondary)
        .disabled(!feedbackEnabled)
        .accessibilityHint("Feedback will be available after the review service launches")
    }
  }

  private func matchCard(_ match: IdentifyMatch, position: Int) -> some View {
    FlukeCard {
      VStack(alignment: .leading, spacing: 8) {
        Text("POSSIBILITY \(position)")
          .font(.flukeLabel)
          .foregroundStyle(Color.tide)
        Text(match.name ?? match.catalogId)
          .font(.flukeDisplaySmall)
        Text(match.name == nil ? "Catalog \(match.catalogId)" : match.catalogId)
          .font(.subheadline.monospaced())
          .foregroundStyle(Color.deep)
        Text("\(Int((match.score * 100).rounded()))% visual similarity")
          .font(.headline)
          .foregroundStyle(Color.ember)
        Text(match.explanation)
          .font(.flukeBody)
          .foregroundStyle(Color.deep)
      }
      .frame(width: 236, alignment: .leading)
    }
    .accessibilityElement(children: .combine)
  }
}
