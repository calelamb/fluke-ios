import FlukeKit
import FlukeUI
import SwiftUI

public struct TraceSubView: View {
    @State private var viewModel: TraceViewModel
    public let catalog: [Whale]

    public init(
        repository: any WhalesRepositoryProtocol,
        catalog: [Whale],
        initialWhaleID: String? = nil
    ) {
        _viewModel = State(initialValue: TraceViewModel(
            repository: repository,
            selectedWhaleID: initialWhaleID
        ))
        self.catalog = catalog
    }

    public var body: some View {
        ZStack(alignment: .top) {
            BasemapView()
            if !viewModel.isSparse {
                AnimatedPolylineLayer(
                    coordinates: viewModel.visiblePoints.map { ($0.latitude, $0.longitude) },
                    color: .tide,
                    isLatest: true
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            VStack(spacing: 8) {
                whalePicker
                stateMessage
                Spacer()
                if let range = viewModel.dateRange, !viewModel.isSparse {
                    DateScrubberAtlas(
                        date: Binding(
                            get: { viewModel.scrubberDate },
                            set: { viewModel.scrubberDate = $0 }
                        ),
                        range: range
                    )
                    .padding(14)
                    .accessibilityLabel("Trace date")
                    .accessibilityValue(viewModel.scrubberDate.formatted(date: .abbreviated, time: .omitted))
                }
            }
        }
        .task(id: catalog.first?.id) {
            if viewModel.selectedWhaleId == nil {
                viewModel.selectedWhaleId = catalog.first?.id
            }
            await viewModel.loadIfNeeded()
        }
    }

    private var whalePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(catalog) { whale in
                    let selected = viewModel.selectedWhaleId == whale.id
                    Button(whale.catalogId) {
                        viewModel.selectedWhaleId = whale.id
                        Task { await viewModel.loadIfNeeded() }
                    }
                        .font(.flukeLabel)
                        .foregroundStyle(selected ? Color.bone : Color.abyss)
                        .padding(.horizontal, 12)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(selected ? Color.abyss : Color.bone, in: Capsule())
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(whale.name ?? "Unnamed whale"), catalog \(whale.catalogId)")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 14)
        }
        .accessibilityLabel("Trace whale")
    }

    @ViewBuilder
    private var stateMessage: some View {
        if catalog.isEmpty {
            Text("The whale catalog is unavailable for trace selection.")
                .font(.flukeBody)
                .padding(12)
                .background(Color.bone.opacity(0.94), in: RoundedRectangle(cornerRadius: 12))
        } else if let notice = viewModel.state.notice {
            switch notice {
            case .offline: BrowseStatusView(kind: .offline) { Task { await viewModel.retry() } }
            case .stale(let failure):
                BrowseStatusView(kind: .stale(failure)) { Task { await viewModel.retry() } }
            }
        } else if let failure = viewModel.state.failure {
            BrowseStatusView(kind: .failure(failure)) { Task { await viewModel.retry() } }
        } else if viewModel.state.isLoading {
            ProgressView("Loading movement trace").padding(12).background(Color.bone, in: Capsule())
        } else if viewModel.isSparse {
            Text("Not enough sightings yet to trace a movement pattern.")
                .font(.flukeBody)
                .padding(12)
                .background(Color.bone.opacity(0.94), in: RoundedRectangle(cornerRadius: 12))
        } else if viewModel.points.isEmpty, viewModel.selectedWhaleId != nil {
            Text("No movement points were returned for this whale.")
                .font(.flukeBody)
                .padding(12)
                .background(Color.bone.opacity(0.94), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
