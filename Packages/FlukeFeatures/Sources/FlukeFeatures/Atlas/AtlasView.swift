import SwiftUI
import FlukeKit
import FlukeUI

public struct AtlasView: View {

    @State private var viewModel = AtlasViewModel()
    @Environment(\.dismiss) private var dismiss

    public let historicalRepo: HistoricalSightingsRepository
    public let predictionRepo: PredictionRepository
    public let whalesRepo: WhalesRepository
    public let catalog: [Whale]

    public init(
        historicalRepo: HistoricalSightingsRepository,
        predictionRepo: PredictionRepository,
        whalesRepo: WhalesRepository,
        catalog: [Whale]
    ) {
        self.historicalRepo = historicalRepo
        self.predictionRepo = predictionRepo
        self.whalesRepo = whalesRepo
        self.catalog = catalog
    }

    public var body: some View {
        ZStack(alignment: .top) {
            // Active sub-view fills the screen
            Group {
                switch viewModel.activeSubView {
                case .timeline:
                    TimelineSubView(repository: historicalRepo, catalog: catalog)
                case .range:
                    RangeSubView(repository: historicalRepo)
                case .trace:
                    TraceSubView(repository: whalesRepo, catalog: catalog)
                case .predict:
                    PredictSubView(repository: predictionRepo, catalog: catalog)
                }
            }
            .ignoresSafeArea()

            // Top chrome — close button + title + segmented control
            VStack(spacing: 8) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.abyss)
                            .padding(8)
                            .background(Color.bone)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Text("Atlas")
                        .font(.flukeDisplaySmall)
                        .foregroundStyle(Color.abyss)

                    Spacer()
                }

                Picker("Sub-view", selection: $viewModel.activeSubView) {
                    ForEach(AtlasViewModel.SubView.allCases) { sv in
                        Text(sv.rawValue).tag(sv)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
        }
    }
}
