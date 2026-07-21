import FlukeUI
import SwiftUI

public struct IdentifyResultsView: View {
  public let result: IdentifyResult
  public let disclaimer: String
  public let openWhale: (String) -> Void

  public init(
    result: IdentifyResult,
    disclaimer: String,
    openWhale: @escaping (String) -> Void
  ) {
    self.result = result
    self.disclaimer = disclaimer
    self.openWhale = openWhale
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      if let prominent = result.prominent {
        prominentCard(prominent)
      }
      if !result.provisional.isEmpty {
        provisionalMatches
      }
      Label(disclaimer, systemImage: "eye.trianglebadge.exclamationmark")
        .font(.callout.weight(.semibold))
        .foregroundStyle(Color.deep)
      artifactDisclosure
    }
  }

  private func prominentCard(_ match: IdentifyResultMatch) -> some View {
    FlukeCard {
      VStack(alignment: .leading, spacing: 10) {
        Text("STABILIZED VISUAL MATCH")
          .font(.flukeLabel)
          .foregroundStyle(Color.tide)
        Text(match.catalogID).font(.flukeDisplaySmall)
        scoreText(match.score)
        Button("Open whale \(match.catalogID)") { openWhale(match.whaleID) }
          .buttonStyle(FlukeButtonStyle.primary)
      }
    }
    .accessibilityIdentifier("identify.result.stabilized")
  }

  private var provisionalMatches: some View {
    VStack(alignment: .leading, spacing: 10) {
      EditorialHeading(level: .section, text: "Provisional top matches")
      ScrollView(.horizontal) {
        LazyHStack(spacing: 12) {
          ForEach(result.provisional) { match in
            FlukeCard {
              VStack(alignment: .leading, spacing: 8) {
                Text("RANK \(match.rank)").font(.flukeLabel).foregroundStyle(Color.tide)
                Text(match.catalogID).font(.flukeDisplaySmall)
                scoreText(match.score)
                Text("References: \(match.referencePhotoIDs.joined(separator: ", "))")
                  .font(.caption.monospaced())
                  .foregroundStyle(Color.deep)
              }
              .frame(width: 236, alignment: .leading)
            }
          }
        }
      }
    }
    .accessibilityIdentifier("identify.results.provisional")
  }

  private func scoreText(_ score: Float) -> some View {
    Text("Similarity score \(score.formatted(.number.precision(.fractionLength(3))))")
      .font(.headline)
      .foregroundStyle(Color.ember)
  }

  private var artifactDisclosure: some View {
    Text(
      "Model \(result.artifact.modelVersion) · Index \(result.artifact.indexVersion) · Manifest \(result.artifact.manifestVersion)"
    )
    .font(.caption.monospaced())
    .foregroundStyle(Color.deep)
  }
}
