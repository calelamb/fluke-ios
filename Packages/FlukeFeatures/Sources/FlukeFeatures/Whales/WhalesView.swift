import FlukeKit
import FlukeUI
import SwiftUI

public struct WhalesView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var viewModel: WhalesViewModel
    private let repository: any WhalesRepositoryProtocol
    private let openSubmit: () -> Void
    private let openTrace: (Whale) -> Void

    public init(
        repository: any WhalesRepositoryProtocol,
        onOpenTrace: @escaping (Whale) -> Void = { _ in },
        onOpenSubmit: @escaping () -> Void = {}
    ) {
        self.repository = repository
        self.openTrace = onOpenTrace
        openSubmit = onOpenSubmit
        _viewModel = State(initialValue: WhalesViewModel(repository: repository))
    }

    public var body: some View {
        VStack(spacing: 0) {
            filters
            status
            content
        }
        .background(Color.fog)
        .navigationTitle("Whales")
        .searchable(text: $viewModel.searchText, prompt: "Name, catalog ID, pod, or ecotype")
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(WhalesViewModel.Filter.allCases) { filter in
                    Button(filter.rawValue) { viewModel.filter = filter }
                        .font(.flukeBody.weight(.semibold))
                        .foregroundStyle(viewModel.filter == filter ? Color.bone : Color.abyss)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(
                            viewModel.filter == filter ? Color.tide : Color.bone,
                            in: Capsule()
                        )
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(viewModel.filter == filter ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .accessibilityLabel("Whale catalog filters")
    }

    @ViewBuilder
    private var status: some View {
        if let notice = viewModel.state.notice {
            switch notice {
            case .offline:
                BrowseStatusView(kind: .offline) { Task { await viewModel.retry() } }
            case .stale(let failure):
                BrowseStatusView(kind: .stale(failure)) { Task { await viewModel.retry() } }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.filteredWhales.isEmpty {
            if viewModel.state.isLoading {
                ProgressView("Loading whale catalog")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let failure = viewModel.state.failure {
                ContentUnavailableView {
                    Label("Catalog unavailable", systemImage: "water.waves")
                } description: {
                    Text(failure.message)
                } actions: {
                    if failure.retryable {
                        Button("Retry") { Task { await viewModel.retry() } }
                    }
                }
            } else {
                ContentUnavailableView(
                    viewModel.serverCatalogIsEmpty ? "No whales available" : "No matching whales",
                    systemImage: "magnifyingglass",
                    description: Text(viewModel.serverCatalogIsEmpty
                        ? "The public catalog is currently empty."
                        : "Try another search or filter.")
                )
            }
        } else {
            ScrollView {
                LazyVGrid(
                    columns: gridColumns,
                    spacing: 14
                ) {
                    ForEach(viewModel.filteredWhales) { whale in
                        NavigationLink {
                            WhaleProfileView(
                                whale: whale,
                                repository: repository,
                                onOpenTrace: { openTrace(whale) },
                                onOpenSubmit: openSubmit
                            )
                        } label: {
                            WhaleCard(whale: whale)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens whale profile")
                    }
                }
                .padding(16)
            }
            .accessibilityIdentifier("whales.loaded")
        }
    }

    private var gridColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [GridItem(.adaptive(minimum: 155, maximum: 260), spacing: 14)]
    }
}
