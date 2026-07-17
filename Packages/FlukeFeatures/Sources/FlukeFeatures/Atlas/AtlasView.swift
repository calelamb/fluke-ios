import FlukeKit
import FlukeUI
import SwiftUI

public struct AtlasView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var viewModel: AtlasViewModel

    private let historicalRepository: any HistoricalSightingsRepositoryProtocol
    private let predictionRepository: any PredictionRepositoryProtocol
    private let whalesRepository: any WhalesRepositoryProtocol
    private let requestedTraceWhaleID: String?

    public init(
        historicalRepository: any HistoricalSightingsRepositoryProtocol,
        predictionRepository: any PredictionRepositoryProtocol,
        whalesRepository: any WhalesRepositoryProtocol,
        requestedTraceWhaleID: String? = nil
    ) {
        self.historicalRepository = historicalRepository
        self.predictionRepository = predictionRepository
        self.whalesRepository = whalesRepository
        self.requestedTraceWhaleID = requestedTraceWhaleID
        _viewModel = State(initialValue: AtlasViewModel(
            repository: whalesRepository,
            activeSubView: requestedTraceWhaleID == nil ? .timeline : .trace
        ))
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            activeMode
        }
        .background(Color.fog)
        .task { await viewModel.loadCatalog() }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("Atlas")
                .font(.flukeDisplaySmall)
                .foregroundStyle(Color.abyss)
                .frame(maxWidth: .infinity, alignment: .leading)

            modePicker
                .accessibilityHint("Changes the public movement visualization")

            catalogStatus
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.fog)
    }

    @ViewBuilder
    private var modePicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Picker("Atlas mode", selection: $viewModel.activeSubView) {
                modeOptions
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Picker("Atlas mode", selection: $viewModel.activeSubView) {
                modeOptions
            }
            .pickerStyle(.segmented)
        }
    }

    private var modeOptions: some View {
        ForEach(AtlasViewModel.SubView.allCases) { mode in
            Text(mode.rawValue).tag(mode)
        }
    }

    @ViewBuilder
    private var activeMode: some View {
        switch viewModel.activeSubView {
        case .timeline:
            TimelineSubView(repository: historicalRepository, catalog: viewModel.catalog)
        case .range:
            RangeSubView(repository: historicalRepository)
        case .trace:
            TraceSubView(
                repository: whalesRepository,
                catalog: viewModel.catalog,
                initialWhaleID: requestedTraceWhaleID
            )
        case .predict:
            PredictSubView(repository: predictionRepository)
        }
    }

    @ViewBuilder
    private var catalogStatus: some View {
        if let notice = viewModel.catalogState.notice {
            switch notice {
            case .offline:
                BrowseStatusView(kind: .offline) { Task { await viewModel.loadCatalog() } }
            case .stale(let failure):
                BrowseStatusView(kind: .stale(failure)) { Task { await viewModel.loadCatalog() } }
            }
        } else if let failure = viewModel.catalogState.failure {
            BrowseStatusView(kind: .failure(failure)) { Task { await viewModel.loadCatalog() } }
        }
    }
}
