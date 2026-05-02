import SwiftUI
import FlukeKit
import FlukeUI

public struct TraceSubView: View {

    @State private var viewModel: TraceViewModel
    public let catalog: [Whale]

    public init(repository: WhalesRepository, catalog: [Whale]) {
        self._viewModel = State(initialValue: TraceViewModel(repository: repository))
        self.catalog = catalog
    }

    public var body: some View {
        ZStack(alignment: .top) {
            BasemapView()

            // Polyline overlay if loaded
            if viewModel.loadState == .loaded {
                let coords = viewModel.visiblePoints.map { ($0.latitude, $0.longitude) }
                AnimatedPolylineLayer(
                    coordinates: coords,
                    color: .tide,
                    isLatest: true
                )
                .allowsHitTesting(false)
            }

            // Whale picker + sparse / scrubber overlays
            VStack(spacing: 8) {
                whalePicker

                if case .sparse(let reason) = viewModel.loadState {
                    Text(reason)
                        .font(.flukeBody)
                        .foregroundStyle(Color.deep)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.bone.opacity(0.95))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 14)
                }

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
    }

    @ViewBuilder
    private var whalePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(catalog) { whale in
                    Button {
                        viewModel.selectedWhaleId = whale.id
                    } label: {
                        Text(whale.catalogId)
                            .font(.flukeLabel.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .foregroundStyle(viewModel.selectedWhaleId == whale.id ? Color.bone : Color.deep)
                            .background(
                                Capsule().fill(viewModel.selectedWhaleId == whale.id ? Color.abyss : Color.bone)
                            )
                            .overlay(
                                Capsule().stroke(Color.mist.opacity(0.5), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
        }
        .padding(.top, 14)
    }
}
