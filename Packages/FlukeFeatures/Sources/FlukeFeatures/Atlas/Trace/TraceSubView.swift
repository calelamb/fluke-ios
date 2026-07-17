import FlukeKit
import FlukeUI
import SwiftUI

public struct TraceSubView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var viewModel: TraceViewModel
  public let catalog: [Whale]
  private let loadsAutomatically: Bool

  public init(
    repository: any WhalesRepositoryProtocol,
    catalog: [Whale],
    initialWhaleID: String? = nil
  ) {
    self.init(
      repository: repository,
      catalog: catalog,
      initialWhaleID: initialWhaleID,
      initialState: .idle,
      loadsAutomatically: true
    )
  }

  init(
    repository: any WhalesRepositoryProtocol,
    catalog: [Whale],
    initialWhaleID: String? = nil,
    initialState: BrowseViewState<[MovementTrackPoint]>,
    loadsAutomatically: Bool
  ) {
    _viewModel = State(
      initialValue: TraceViewModel(
        repository: repository,
        selectedWhaleID: initialWhaleID,
        initialState: initialState
      ))
    self.catalog = catalog
    self.loadsAutomatically = loadsAutomatically
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
        stateMessage
        Spacer()
        AtlasControlShelf {
          whalePicker
          selectedPodLegend
          Text(viewModel.accessibilitySummary(catalog: catalog))
            .font(.flukeLabel)
            .foregroundStyle(Color.deep)
            .accessibilityIdentifier("atlas.trace.summary")
          if let range = viewModel.dateRange, !viewModel.isSparse {
            DateScrubberAtlas(
              date: Binding(
                get: { viewModel.scrubberDate },
                set: { viewModel.scrubberDate = $0 }
              ),
              range: range
            )
            .accessibilityLabel("Trace date")
            .accessibilityValue(
              viewModel.scrubberDate.formatted(date: .abbreviated, time: .omitted))
          }
        }
        .padding(.bottom, 12)
      }
    }
    .task(id: catalog.first?.id) {
      guard loadsAutomatically else { return }
      if viewModel.selectedWhaleId == nil {
        viewModel.selectedWhaleId = catalog.first?.id
        return
      }
      await viewModel.loadIfNeeded()
    }
    .onChange(of: viewModel.selectedWhaleId) { _, _ in
      guard loadsAutomatically else { return }
      Task { await viewModel.loadIfNeeded() }
    }
  }

  @ViewBuilder
  private var selectedPodLegend: some View {
    if let whale = catalog.first(where: { $0.id == viewModel.selectedWhaleId }),
      let pod = pod(for: whale)
    {
      AtlasPodLegend(counts: [pod: viewModel.visiblePoints.count])
    }
  }

  private func pod(for whale: Whale) -> Pod? {
    switch whale.pod {
    case "J": .j
    case "K": .k
    case "L": .l
    default: whale.ecotype == .biggs ? .biggs : nil
    }
  }

  private var whalePicker: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        Picker("Trace whale", selection: $viewModel.selectedWhaleId) {
          ForEach(catalog) { whale in Text(whale.catalogId).tag(Optional(whale.id)) }
        }
        .pickerStyle(.menu)
        .frame(minHeight: 44)
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) { whaleButtons }
        }
      }
    }
    .accessibilityLabel("Trace whale")
  }

  private var whaleButtons: some View {
    ForEach(catalog) { whale in
      let selected = viewModel.selectedWhaleId == whale.id
      Button(whale.catalogId) {
        viewModel.selectedWhaleId = whale.id
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

  @ViewBuilder
  private var stateMessage: some View {
    let composition = viewModel.statusComposition(hasCatalog: !catalog.isEmpty)
    if let notice = composition.notice {
      switch notice {
      case .offline: BrowseStatusView(kind: .offline) { Task { await viewModel.retry() } }
      case .stale(let failure):
        BrowseStatusView(kind: .stale(failure)) { Task { await viewModel.retry() } }
      }
    }
    if let failure = viewModel.state.failure {
      BrowseStatusView(kind: .failure(failure)) { Task { await viewModel.retry() } }
    } else if viewModel.state.isLoading {
      ProgressView("Loading movement trace").padding(12).background(Color.bone, in: Capsule())
    } else if let truth = composition.truth {
      Text(truth.message)
        .font(.flukeBody)
        .padding(12)
        .background(Color.bone.opacity(0.94), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("atlas.trace.truth")
    }
  }
}
