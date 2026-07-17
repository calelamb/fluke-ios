import FlukeKit
import FlukeUI
import SwiftUI

public struct PredictSubView: View {
    @State private var viewModel: PredictViewModel

    public init(repository: any PredictionRepositoryProtocol) {
        _viewModel = State(initialValue: PredictViewModel(repository: repository))
    }

    public var body: some View {
        ZStack(alignment: .top) {
            BasemapView()
            if let prediction = viewModel.prediction {
                ConfidenceCone(cells: prediction.cells, color: .ember)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            ScrollView(.vertical) {
                VStack(spacing: 8) {
                    subjectPicker
                    horizonPicker
                    stateMessage
                    if let prediction = viewModel.prediction {
                        confidenceBlock(prediction)
                    }
                }
                .padding(.horizontal, 14)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .task {
            if viewModel.subject == nil { viewModel.subject = .pod(.j) }
            await viewModel.loadIfNeeded()
        }
    }

    private var subjectPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Pod.allCases, id: \.self) { pod in
                    let selected = viewModel.subject == .pod(pod)
                    Button(pod.displayName) {
                        viewModel.subject = .pod(pod)
                        Task { await viewModel.loadIfNeeded() }
                    }
                    .font(.flukeLabel)
                    .foregroundStyle(selected ? Color.bone : Color.abyss)
                    .padding(.horizontal, 12)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(selected ? Color.abyss : Color.bone, in: Capsule())
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .accessibilityLabel("Prediction subject")
    }

    private var horizonPicker: some View {
        HStack(spacing: 8) {
            ForEach(PredictionHorizon.allCases, id: \.self) { horizon in
                let selected = viewModel.horizon == horizon
                Button(horizon.displayName) {
                    viewModel.horizon = horizon
                    Task { await viewModel.loadIfNeeded() }
                }
                .font(.flukeLabel)
                .foregroundStyle(selected ? Color.bone : Color.abyss)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(selected ? Color.tide : Color.bone, in: Capsule())
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .accessibilityLabel("Prediction horizon")
    }

    @ViewBuilder
    private var stateMessage: some View {
        if let notice = viewModel.state.notice {
            switch notice {
            case .offline: BrowseStatusView(kind: .offline) { Task { await viewModel.retry() } }
            case .stale(let failure):
                BrowseStatusView(kind: .stale(failure)) { Task { await viewModel.retry() } }
            }
        } else if let failure = viewModel.state.failure {
            BrowseStatusView(kind: .failure(failure)) { Task { await viewModel.retry() } }
        } else if viewModel.state.isLoading {
            ProgressView("Loading prediction").padding(12).background(Color.bone, in: Capsule())
        } else if viewModel.isEmpty {
            Text("Not enough data to show a prediction for this subject and horizon.")
                .font(.flukeBody)
                .padding(12)
                .background(Color.bone.opacity(0.94), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func confidenceBlock(_ prediction: Prediction) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("A data summary of where this subject has tended to be in the current month, based on \(prediction.cells.count) historical cells.")
                .font(.flukeBody)
                .foregroundStyle(Color.abyss)
            Text("Confidence: \(confidenceLabel(prediction.confidence)) · model: \(prediction.modelVersion)")
                .font(.flukeLabel)
                .foregroundStyle(Color.deep)
        }
        .padding(14)
        .background(Color.bone.opacity(0.95), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private func confidenceLabel(_ value: Double) -> String {
        if value >= 0.7 { return "high" }
        if value >= 0.4 { return "medium" }
        return "low"
    }
}
