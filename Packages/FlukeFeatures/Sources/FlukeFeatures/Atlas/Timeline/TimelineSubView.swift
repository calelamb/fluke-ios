import SwiftUI
import FlukeKit
import FlukeUI

public struct TimelineSubView: View {

    @State private var viewModel: TimelineViewModel
    public let catalog: [Whale]

    public init(repository: HistoricalSightingsRepository, catalog: [Whale]) {
        self._viewModel = State(initialValue: TimelineViewModel(repository: repository))
        self.catalog = catalog
    }

    public var body: some View {
        ZStack {
            BasemapView()

            // Polyline overlays on top of basemap (rendered via overlay positioning)
            GeometryReader { geo in
                ZStack {
                    let tracks = viewModel.tracks(catalog: catalog)
                    ForEach(Array(tracks.keys), id: \.self) { pod in
                        AnimatedPolylineLayer(
                            coordinates: tracks[pod]!.map { ($0.lat, $0.lng) },
                            color: AtlasPodColor.color(for: pod),
                            isLatest: true
                        )
                        .id("\(pod.rawValue)-\(viewModel.scrubberDate.timeIntervalSince1970.rounded())")
                    }
                }
            }
            .allowsHitTesting(false)

            // Scrubber overlay
            VStack {
                Spacer()
                if let range = viewModel.dateRange {
                    DateScrubberAtlas(
                        date: Binding(
                            get: { viewModel.scrubberDate },
                            set: { viewModel.scrubberDate = $0 }
                        ),
                        range: range
                    )
                    .padding(14)
                }
            }
        }
        .task { await viewModel.load() }
    }
}
