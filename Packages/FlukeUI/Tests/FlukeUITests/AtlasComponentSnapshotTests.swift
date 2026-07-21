import FlukeKit
import SnapshotTesting
import SwiftUI
import XCTest

@testable import FlukeUI

@MainActor
final class AtlasComponentSnapshotTests: XCTestCase {
    func test_atlasComponents() throws {
        let size = CGSize(width: 430, height: 620)
        let image = try renderedSnapshot(
            AtlasComponentGallery()
                .frame(width: size.width, height: size.height),
            size: size
        )

        assertSnapshot(of: image, as: releaseImageSnapshot, named: releaseSnapshotName())
    }
}

private struct AtlasComponentGallery: View {
    private let start = Date(timeIntervalSince1970: 315_576_000)
    private let end = Date(timeIntervalSince1970: 1_735_732_800)
    @State private var date = Date(timeIntervalSince1970: 1_262_347_200)

    var body: some View {
        VStack(spacing: 16) {
            ZStack(alignment: .topLeading) {
                Color.fog
                HeatCell(x: 0.25, y: 0.3, color: .tide, intensity: -1)
                HeatCell(x: 0.7, y: 0.65, color: .ember, intensity: 2)
                ConfidenceCone(cells: predictionCells)
                PodLegend(entries: [
                    .init(label: "J pod", count: 12, color: .tide),
                    .init(label: "Bigg's", count: 7, color: .ember),
                ])
                .padding(12)
            }
            .frame(height: 430)

            DateScrubberAtlas(date: $date, range: start...end)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.fog)
    }

    private var predictionCells: [PredictionCell] {
        [
            PredictionCell(lat: 48.7, lng: -123.2, probability: 1),
            PredictionCell(lat: 48.5, lng: -123.4, probability: 0.5),
            PredictionCell(lat: 48.3, lng: -123.0, probability: 0.3),
            PredictionCell(lat: 48.1, lng: -122.8, probability: 0.1),
        ]
    }
}
