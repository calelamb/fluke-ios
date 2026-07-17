import FlukeKit
import SnapshotTesting
import SwiftUI
import XCTest

@testable import FlukeUI

@MainActor
final class AtlasVisualSnapshotTests: XCTestCase {
  func test_atlasEditorialControlShelf() throws {
    FlukeUIFontRegistration.registerIfNeeded()
    let size = CGSize(width: 430, height: 420)
    let image = try renderedSnapshot(
      AtlasEditorialGallery()
        .frame(width: size.width, height: size.height),
      size: size
    )

    assertSnapshot(of: image, as: releaseImageSnapshot)
  }
}

private struct AtlasEditorialGallery: View {
  private let start = Date(timeIntervalSince1970: 1_735_689_600)
  private let end = Date(timeIntervalSince1970: 1_767_225_600)
  @State private var date = Date(timeIntervalSince1970: 1_751_457_600)

  var body: some View {
    ZStack(alignment: .bottom) {
      Color.tide.opacity(0.12)
      ConfidenceCone(cells: cells, color: .ember)
      VStack(spacing: 12) {
        HStack {
          Text("Haro Strait")
            .font(.custom("Fraunces", size: 18, relativeTo: .headline))
            .italic()
          Spacer()
          PodLegend(entries: [
            .init(label: "J pod", count: 4, color: .tide),
            .init(label: "K pod", count: 2, color: .deep),
            .init(label: "L pod", count: 1, color: .swell),
            .init(label: "Bigg's", count: 3, color: .ember),
          ])
        }
        Spacer()
        DateScrubberAtlas(date: $date, range: start...end)
      }
      .padding(16)
    }
    .background(Color.fog)
  }

  private var cells: [PredictionCell] {
    [
      PredictionCell(lat: 48.7, lng: -123.2, probability: 0.9),
      PredictionCell(lat: 48.5, lng: -123.4, probability: 0.5),
      PredictionCell(lat: 48.3, lng: -123.0, probability: 0.25),
    ]
  }
}
