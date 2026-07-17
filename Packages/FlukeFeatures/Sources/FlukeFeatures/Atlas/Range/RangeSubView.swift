import FlukeKit
import FlukeUI
import SwiftUI

public struct RangeSubView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var viewModel: RangeViewModel

  public init(repository: any HistoricalSightingsRepositoryProtocol) {
    _viewModel = State(initialValue: RangeViewModel(repository: repository))
  }

  public var body: some View {
    ZStack(alignment: .top) {
      BasemapView()
      heatmapLayer
      VStack(spacing: 8) {
        stateMessage
        Spacer()
        AtlasControlShelf {
          podPicker
          monthChips
          AtlasPodLegend(counts: [
            viewModel.selectedPod: viewModel.heatmap.reduce(0) { $0 + $1.count }
          ])
          Text(viewModel.accessibilitySummary)
            .font(.flukeLabel)
            .foregroundStyle(Color.deep)
            .accessibilityIdentifier("atlas.range.summary")
        }
        .padding(.bottom, 12)
      }
    }
    .task { await viewModel.load() }
    .onChange(of: viewModel.selectedPod) { _, _ in
      Task { await viewModel.load() }
    }
  }

  private var heatmapLayer: some View {
    ZStack {
      ForEach(Array(viewModel.heatmap.enumerated()), id: \.offset) { _, cell in
        let point = RangeGridProjection.normalizedCenter(x: cell.x, y: cell.y)
        HeatCell(
          x: CGFloat(point.x),
          y: CGFloat(point.y),
          color: AtlasPodColor.color(for: viewModel.selectedPod),
          intensity: RangeHeatmapPresentation.intensity(
            count: cell.count,
            maximum: viewModel.maxCount
          )
        )
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private var podPicker: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        Picker("Range pod", selection: $viewModel.selectedPod) {
          ForEach(Pod.allCases, id: \.self) { pod in Text(pod.displayName).tag(pod) }
        }
        .pickerStyle(.menu)
        .frame(minHeight: 44)
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 6) {
            ForEach(Pod.allCases, id: \.self) { pod in
              let selected = viewModel.selectedPod == pod
              Button(pod.displayName) { viewModel.selectedPod = pod }
                .font(.flukeLabel)
                .foregroundStyle(selected ? Color.bone : Color.abyss)
                .padding(.horizontal, 12)
                .frame(minWidth: 44, minHeight: 44)
                .background(selected ? AtlasPodColor.color(for: pod) : Color.bone, in: Capsule())
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
          }
        }
      }
    }
    .accessibilityLabel("Range pod")
  }

  private var monthChips: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        Menu("Visible months") { monthButtons }
          .frame(minHeight: 44)
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 6) { monthButtons }
        }
      }
    }
    .accessibilityLabel("Visible months")
  }

  private var monthButtons: some View {
    ForEach(1...12, id: \.self) { month in
      let selected = viewModel.activeMonths.contains(month)
      Button(monthShort(month)) { viewModel.toggleMonth(month) }
        .font(.flukeLabel)
        .foregroundStyle(selected ? Color.abyss : Color.deep)
        .padding(.horizontal, 10)
        .frame(minWidth: 44, minHeight: 44)
        .background(selected ? Color.bone : Color.fog, in: Capsule())
        .buttonStyle(.plain)
        .accessibilityLabel(monthName(month))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
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
      ProgressView("Loading range").padding(12).background(Color.bone, in: Capsule())
    } else if viewModel.sightings.isEmpty {
      Text("No range data for this pod and window.")
        .font(.flukeBody)
        .padding(12)
        .background(Color.bone.opacity(0.94), in: RoundedRectangle(cornerRadius: 12))
    }
  }

  private func monthShort(_ month: Int) -> String {
    Calendar.current.shortMonthSymbols[month - 1]
  }

  private func monthName(_ month: Int) -> String {
    Calendar.current.monthSymbols[month - 1]
  }
}
