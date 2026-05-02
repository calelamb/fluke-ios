import SwiftUI
import FlukeKit
import FlukeUI

public struct PredictSubView: View {

    @State private var viewModel: PredictViewModel
    public let catalog: [Whale]

    public init(repository: PredictionRepository, catalog: [Whale]) {
        self._viewModel = State(initialValue: PredictViewModel(repository: repository))
        self.catalog = catalog
    }

    public var body: some View {
        ZStack(alignment: .top) {
            BasemapView()

            // Confidence cone overlay if loaded
            if case .loaded(let prediction) = viewModel.loadState {
                ConfidenceCone(cells: prediction.cells, color: .ember)
                    .allowsHitTesting(false)
            }

            VStack(spacing: 8) {
                subjectAndHorizonPickers

                if case .loaded(let prediction) = viewModel.loadState {
                    confidenceBlock(prediction: prediction)
                }
                if case .empty(let reason) = viewModel.loadState {
                    Text(reason)
                        .font(.flukeBody)
                        .foregroundStyle(Color.deep)
                        .padding(20)
                        .frame(maxWidth: .infinity)
                        .background(Color.bone.opacity(0.95))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 14)
                }

                Spacer()
            }
            .padding(14)
        }
    }

    @ViewBuilder
    private var subjectAndHorizonPickers: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(Pod.allCases, id: \.self) { pod in
                    let isActive: Bool = {
                        if case .pod(let p) = viewModel.subject, p == pod { return true } else { return false }
                    }()
                    Button {
                        viewModel.subject = .pod(pod)
                    } label: {
                        Text(pod.displayName)
                            .font(.flukeLabel.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .foregroundStyle(isActive ? Color.bone : Color.deep)
                            .background(Capsule().fill(isActive ? Color.abyss : Color.bone))
                            .overlay(Capsule().stroke(Color.mist.opacity(0.5), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 6) {
                ForEach(PredictionHorizon.allCases, id: \.self) { h in
                    Button {
                        viewModel.horizon = h
                        Task { await viewModel.loadIfNeeded() }
                    } label: {
                        Text(h.displayName)
                            .font(.flukeLabel)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .foregroundStyle(viewModel.horizon == h ? Color.abyss : Color.deep)
                            .background(Capsule().fill(viewModel.horizon == h ? Color.bone : Color.fog))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func confidenceBlock(prediction: Prediction) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Roughly where this subject has tended to be in the current month, based on \(prediction.cells.count) historical cells.")
                .font(.flukeBody)
                .foregroundStyle(Color.abyss)
                .fixedSize(horizontal: false, vertical: true)
            Text("Confidence: \(confidenceLabel(prediction.confidence)) · model: \(prediction.modelVersion)")
                .font(.flukeLabel)
                .foregroundStyle(Color.deep)
        }
        .padding(14)
        .background(Color.bone.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func confidenceLabel(_ c: Double) -> String {
        if c >= 0.7 { return "high" }
        if c >= 0.4 { return "medium" }
        return "low"
    }
}
