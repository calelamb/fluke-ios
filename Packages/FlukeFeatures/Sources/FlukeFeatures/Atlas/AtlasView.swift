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
    _viewModel = State(
      initialValue: AtlasViewModel(
        repository: whalesRepository,
        activeSubView: requestedTraceWhaleID == nil ? .timeline : .trace
      ))
  }

  public var body: some View {
    VStack(spacing: 0) {
      header
      activeMode
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(viewModel.activeSubView.rawValue) Atlas mode")
        .accessibilityIdentifier("atlas.active.surface")
    }
    .background(Color.fog)
    .task { await viewModel.loadCatalog() }
    .accessibilityIdentifier("atlas.fullScreen")
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
      Menu {
        ForEach(AtlasViewModel.SubView.allCases) { mode in
          Button(mode.rawValue) { viewModel.activeSubView = mode }
            .accessibilityAddTraits(viewModel.activeSubView == mode ? .isSelected : [])
        }
      } label: {
        Label("Atlas mode: \(viewModel.activeSubView.rawValue)", systemImage: "map")
          .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityIdentifier("atlas.mode.picker")
    } else {
      Picker("Atlas mode", selection: $viewModel.activeSubView) {
        modeOptions
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier("atlas.mode.picker")
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
      PredictSubView(repository: predictionRepository, catalog: viewModel.catalog)
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

struct AtlasControlShelf<Content: View>: View {
  @ViewBuilder let content: Content
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      content
    }
    .padding(12)
    .background(
      reduceTransparency ? AnyShapeStyle(Color.bone) : AnyShapeStyle(.ultraThinMaterial),
      in: RoundedRectangle(cornerRadius: 18, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(Color.mist.opacity(0.55), lineWidth: 0.5)
    }
    .padding(.horizontal, 12)
  }
}

struct AtlasPodLegend: View {
  let counts: [Pod: Int]

  var body: some View {
    PodLegend(
      entries: Pod.allCases.map { pod in
        .init(
          label: pod.displayName,
          count: counts[pod, default: 0],
          color: AtlasPodColor.color(for: pod)
        )
      }
    )
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(summary)
  }

  private var summary: String {
    Pod.allCases
      .map { "\($0.displayName), \(counts[$0, default: 0])" }
      .joined(separator: "; ")
  }
}
