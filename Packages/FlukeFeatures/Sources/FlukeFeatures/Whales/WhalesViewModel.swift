import FlukeKit
import Foundation
import Observation

@MainActor
@Observable
public final class WhalesViewModel {
    public enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case resident = "Resident"
        case biggs = "Bigg's"
        case offshore = "Offshore"
        case unknown = "Unknown"

        public var id: String { rawValue }

        public var ecotype: Ecotype? {
            switch self {
            case .all: nil
            case .resident: .resident
            case .biggs: .biggs
            case .offshore: .offshore
            case .unknown: .unknown
            }
        }
    }

    public private(set) var state: BrowseViewState<[Whale]> = .idle
    public var searchText = ""
    public var filter: Filter = .all

    private let repository: any WhalesRepositoryProtocol
    private var loadGeneration = 0

    public init(repository: any WhalesRepositoryProtocol) {
        self.repository = repository
    }

    public func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        state = state.beginRefresh()
        let result: BrowseResult<[Whale]>
        do {
            result = try await repository.loadCatalog()
        } catch {
            result = .failed(.unexpectedFeatureFailure)
        }
        guard generation == loadGeneration else { return }
        state = .resolve(result)
    }

    public func retry() async {
        await load()
    }

    public var filteredWhales: [Whale] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return (state.value ?? [])
            .filter { whale in
                let matchesFilter = filter.ecotype.map { whale.ecotype == $0 } ?? true
                guard matchesFilter, !query.isEmpty else { return matchesFilter }
                return [
                    whale.catalogId,
                    whale.name,
                    whale.pod,
                    whale.ecotype.flukeDisplayName,
                ]
                .compactMap { $0 }
                .contains { $0.localizedStandardContains(query) }
            }
            .sorted {
                let order = $0.catalogId.localizedStandardCompare($1.catalogId)
                if order == .orderedSame { return $0.id < $1.id }
                return order == .orderedAscending
            }
    }

    public var serverCatalogIsEmpty: Bool {
        if case .empty = state { return true }
        return false
    }
}
