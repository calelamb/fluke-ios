import FlukeKit
import FlukeUI
import Observation
import SwiftUI

public struct SightingsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var viewModel: SightingsViewModel
    @State private var movementRouter = SightingMovementPresentationRouter()
    private let openWhaleMovement: ((String) -> Void)?

    public init(
        repository: any SightingsRepositoryProtocol,
        onOpenWhaleMovement: ((String) -> Void)? = nil
    ) {
        _viewModel = State(initialValue: SightingsViewModel(repository: repository))
        openWhaleMovement = onOpenWhaleMovement
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
        List(viewModel.items) { item in
            Button {
                viewModel.selectedItem = item
            } label: {
                SightingRow(item: item)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.accessibilityLabel)
            .accessibilityHint("Opens sighting details")
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("sightings.loaded")
    }

    @ViewBuilder
    private var statusViews: some View {
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
