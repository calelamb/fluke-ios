import FlukeKit
import FlukeReleaseB
import FlukeUI
import Observation
import SwiftUI

public struct SightingsView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var viewModel: SightingsViewModel
  @State private var movementRouter = SightingMovementPresentationRouter()
  private let openWhaleMovement: ((String) -> Void)?
  private let feedPoller: FeedPollingActor?
  private let feedLifecycle: FeedLifecycle

  public init(
    repository: any SightingsRepositoryProtocol,
    onOpenWhaleMovement: ((String) -> Void)? = nil
  ) {
    _viewModel = State(initialValue: SightingsViewModel(repository: repository))
    openWhaleMovement = onOpenWhaleMovement
    feedPoller = nil
    feedLifecycle = FeedLifecycle(visible: false, foreground: false)
  }

  public init(
    feedRepository: any SightingFeedRepositoryProtocol,
    isVisible: Bool = true,
    isForeground: Bool = true,
    onOpenWhaleMovement: ((String) -> Void)? = nil
  ) {
    let model = SightingsViewModel(feedRepository: feedRepository)
    _viewModel = State(initialValue: model)
    openWhaleMovement = onOpenWhaleMovement
    feedPoller = FeedPollingActor(refresh: { [weak model] in
      guard let model else { return }
      try await model.pollRefresh()
    })
    feedLifecycle = FeedLifecycle(visible: isVisible, foreground: isForeground)
  }

  public var body: some View {
    VStack(spacing: 0) {
      modePicker
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityHint("Switch between a chronological list and map")

      statusViews

      content
    }
    .background(Color.fog)
    .navigationTitle("Sightings")
    .task { await viewModel.load() }
    .task(id: feedLifecycle) {
      guard let feedPoller else { return }
      await feedPoller.maintainLifecycle(
        visible: feedLifecycle.visible,
        foreground: feedLifecycle.foreground
      )
    }
    .refreshable { await viewModel.load() }
    .sheet(item: $viewModel.selectedItem, onDismiss: openPendingMovement) { item in
      SightingDetailView(item: item, onOpenWhaleMovement: detailMovementAction)
        .presentationDetents([.medium, .large])
    }
  }

  private var detailMovementAction: ((String) -> Void)? {
    guard openWhaleMovement != nil else { return nil }
    return movementRouter.request
  }

  private func openPendingMovement() {
    movementRouter.detailDidDismiss(open: openWhaleMovement)
  }

  @ViewBuilder
  private var modePicker: some View {
    if dynamicTypeSize.isAccessibilitySize {
      Picker("Sightings presentation", selection: $viewModel.mode) {
        modeOptions
      }
      .pickerStyle(.menu)
      .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      Picker("Sightings presentation", selection: $viewModel.mode) {
        modeOptions
      }
      .pickerStyle(.segmented)
    }
  }

  private var modeOptions: some View {
    ForEach(SightingsViewModel.Mode.allCases) { mode in
      Text(mode.rawValue).tag(mode)
    }
  }

  @ViewBuilder
  private var content: some View {
    if viewModel.items.isEmpty {
      if viewModel.isLoading {
        ProgressView("Loading public sightings")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .accessibilityLabel("Loading public sightings")
      } else if let failure = viewModel.primaryFailure, !viewModel.hasConfirmedEmptyFeed {
        ContentUnavailableView {
          Label("Sightings unavailable", systemImage: "binoculars")
        } description: {
          Text(failure.message)
        } actions: {
          if failure.retryable {
            Button("Retry") { Task { await viewModel.retry() } }
          }
        }
      } else {
        ContentUnavailableView(
          "No recent sightings",
          systemImage: "water.waves",
          description: Text("No public sightings were returned for the current window.")
        )
      }
    } else if viewModel.mode == .list {
      sightingsList
    } else {
      SightingsMapView(items: viewModel.items) { item in
        viewModel.selectedItem = item
      }
    }
  }

  private var sightingsList: some View {
    List {
      ForEach(viewModel.items) { item in
        Button {
          viewModel.selectedItem = item
        } label: {
          SightingRow(item: item)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityHint("Opens sighting details")
      }
      historyFooter
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .accessibilityIdentifier("sightings.loaded")
  }

  @ViewBuilder
  private var historyFooter: some View {
    if let failure = viewModel.loadMoreFailure {
      VStack(spacing: 8) {
        Text(failure.message)
        Button("Retry older sightings") { Task { await viewModel.loadMore() } }
      }
      .frame(maxWidth: .infinity)
      .accessibilityHint("Retries loading older sightings")
    } else if viewModel.hasMoreHistory {
      HStack(spacing: 10) {
        ProgressView()
        Text("Loading older sightings")
      }
      .frame(maxWidth: .infinity)
      .accessibilityIdentifier("sightings.load-more")
      .task { await viewModel.loadMore() }
    }
  }

  @ViewBuilder
  private var statusViews: some View {
    if viewModel.feedState != nil {
      Text(freshnessLabel)
        .font(.flukeLabel)
        .foregroundStyle(viewModel.freshness == .live ? Color.tide : Color.deep)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .accessibilityLabel("Sightings freshness: \(freshnessLabel)")
    }
    ForEach(Array(viewModel.notices.enumerated()), id: \.offset) { _, notice in
      switch notice {
      case .offline:
        BrowseStatusView(kind: .offline) { Task { await viewModel.retry() } }
      case .stale(let failure):
        BrowseStatusView(kind: .stale(failure)) { Task { await viewModel.retry() } }
      }
    }
    if let failure = viewModel.primaryFailure, !viewModel.items.isEmpty {
      BrowseStatusView(kind: .failure(failure)) { Task { await viewModel.retry() } }
    }
  }

  private var freshnessLabel: String {
    switch viewModel.freshness {
    case .live:
      return "Live"
    case .recent(let age):
      guard let age else { return "Recent" }
      if age < 60 { return "Recent · updated \(age)s ago" }
      if age < 3_600 { return "Recent · updated \(age / 60)m ago" }
      if age < 86_400 { return "Recent · updated \(age / 3_600)h ago" }
      return "Recent · updated \(age / 86_400)d ago"
    }
  }
}

private struct FeedLifecycle: Hashable {
  let visible: Bool
  let foreground: Bool
}

@MainActor
@Observable
final class SightingMovementPresentationRouter {
  private(set) var pendingCatalogID: String?

  func request(catalogID: String) {
    pendingCatalogID = catalogID
  }

  func detailDidDismiss(open: ((String) -> Void)?) {
    guard let pendingCatalogID else { return }
    self.pendingCatalogID = nil
    open?(pendingCatalogID)
  }
}

private struct SightingRow: View {
  let item: SightingsViewModel.DisplayItem

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: "location.fill")
        .foregroundStyle(Color.tide)
        .frame(width: 34, height: 34)
        .background(Color.tide.opacity(0.12), in: Circle())
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 5) {
        Text(item.locationLabel)
          .font(.flukeDisplaySmall)
          .foregroundStyle(Color.abyss)
        Text(item.observedAt.formatted(date: .abbreviated, time: .shortened))
          .font(.flukeBody)
          .foregroundStyle(Color.deep)
        HStack(spacing: 8) {
          Text(item.sourceLabel)
          if let group = item.groupSize { Text("Group \(group)") }
          if let ecotype = item.ecotype { Text(ecotype.flukeDisplayName) }
        }
        .font(.flukeLabel)
        .foregroundStyle(Color.deep)
        if !item.whaleCatalogIDs.isEmpty {
          Text("Whales \(item.whaleCatalogIDs.joined(separator: ", "))")
            .font(.flukeLabel)
            .foregroundStyle(Color.deep)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 8)
    .contentShape(Rectangle())
    .accessibilityElement(children: .ignore)
  }
}
