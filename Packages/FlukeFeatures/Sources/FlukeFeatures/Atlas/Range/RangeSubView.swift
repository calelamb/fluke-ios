import SwiftUI
import FlukeKit
import FlukeUI

public struct RangeSubView: View {

    @State private var viewModel: RangeViewModel

    public init(repository: HistoricalSightingsRepository) {
        self._viewModel = State(initialValue: RangeViewModel(repository: repository))
    }

    public var body: some View {
        ZStack(alignment: .top) {
            BasemapView()

            // Heatmap overlay
            heatmapLayer

            // Filter chrome on top
            VStack(spacing: 8) {
                podPicker
                monthChips
                Spacer()
            }
            .padding(14)
        }
        .task { await viewModel.load() }
        .onChange(of: viewModel.selectedPod) { _, _ in
            Task { await viewModel.load() }
        }
    }

    @ViewBuilder
    private var heatmapLayer: some View {
        ForEach(viewModel.heatmap, id: \.x) { cell in
            HeatCell(
                x: CGFloat(cell.x) * 0.018 + 0.009,
                y: CGFloat(cell.y) * 0.018 + 0.009,
                color: AtlasPodColor.color(for: viewModel.selectedPod),
                intensity: Double(cell.count) / Double(viewModel.maxCount)
            )
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var podPicker: some View {
        HStack(spacing: 6) {
            ForEach(Pod.allCases, id: \.self) { pod in
                Button {
                    viewModel.selectedPod = pod
                } label: {
                    Text(pod.displayName)
                        .font(.flukeLabel.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .foregroundStyle(viewModel.selectedPod == pod ? Color.bone : Color.deep)
                        .background(Capsule().fill(viewModel.selectedPod == pod ? AtlasPodColor.color(for: pod) : Color.bone))
                        .overlay(Capsule().stroke(Color.mist.opacity(0.5), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var monthChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(1...12, id: \.self) { month in
                    Button {
                        viewModel.toggleMonth(month)
                    } label: {
                        Text(monthShort(month))
                            .font(.flukeLabel)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .foregroundStyle(viewModel.activeMonths.contains(month) ? Color.abyss : Color.mist)
                            .background(Capsule().fill(viewModel.activeMonths.contains(month) ? Color.bone : Color.fog))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func monthShort(_ m: Int) -> String {
        let f = DateFormatter()
        return f.shortMonthSymbols[m - 1]
    }
}
