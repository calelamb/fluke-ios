import FlukeKit
import FlukeUI
import SwiftUI

public struct TimelineSubView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var viewModel: TimelineViewModel
  public let catalog: [Whale]

  public init(
    repository: any HistoricalSightingsRepositoryProtocol,
    catalog: [Whale]
  ) {
    _viewModel = State(initialValue: TimelineViewModel(repository: repository))
    self.catalog = catalog
  }

  public var body: some View {
    ZStack {
      BasemapView()
      tracks
      VStack(spacing: 8) {
        stateMessage
        Spacer()
        AtlasControlShelf {
          podFilters
          AtlasPodLegend(counts: viewModel.podCounts(catalog: catalog))
          Text(viewModel.accessibilitySummary(catalog: catalog))
            .font(.flukeLabel)
            .foregroundStyle(Color.deep)
            .accessibilityIdentifier("atlas.timeline.summary")
          if let range = viewModel.dateRange {
            DateScrubberAtlas(
              date: Binding(
                get: { viewModel.scrubberDate },
                set: { viewModel.scrubberDate = $0 }
              ),
              range: range
            )
            .accessibilityLabel("Timeline date")
            .accessibilityValue(
              viewModel.scrubberDate.formatted(date: .abbreviated, time: .omitted)
            )
            .accessibilityIdentifier("atlas.timeline.loaded")
          }
        }
        .padding(.bottom, 12)
      }
    }
    .task { await viewModel.load() }
  }

  private var tracks: some View {
    let values = viewModel.tracks(catalog: catalog).sorted { $0.key.rawValue < $1.key.rawValue }
    return ZStack {
      ForEach(values, id: \.key) { pod, points in
        AnimatedPolylineLayer(
          coordinates: points.map { ($0.lat, $0.lng) },
          color: AtlasPodColor.color(for: pod),
          isLatest: true
        )
        .id("\(pod.rawValue)-\(viewModel.scrubberDate.timeIntervalSince1970.rounded())")
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private var podFilters: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        Menu("Visible pods") {
          podFilterButtons
        }
        .frame(minHeight: 44)
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) { podFilterButtons }
        }
      }
    }
    .accessibilityLabel("Visible pods")
  }

  private var podFilterButtons: some View {
    ForEach(Pod.allCases, id: \.self) { pod in
      let selected = viewModel.activePods.contains(pod)
      Button(pod.displayName) { viewModel.togglePod(pod) }
        .font(.flukeLabel)
        .foregroundStyle(selected ? Color.bone : Color.abyss)
        .padding(.horizontal, 12)
        .frame(minWidth: 44, minHeight: 44)
        .background(selected ? AtlasPodColor.color(for: pod) : Color.bone, in: Capsule())
        .buttonStyle(.plain)
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
      ProgressView("Loading timeline").padding(12).background(Color.bone, in: Capsule())
    } else if viewModel.historicalSightings.isEmpty {
      Text("No historical sightings in this window.")
        .font(.flukeBody)
        .padding(12)
        .background(Color.bone.opacity(0.94), in: RoundedRectangle(cornerRadius: 12))
    }
  }
}
