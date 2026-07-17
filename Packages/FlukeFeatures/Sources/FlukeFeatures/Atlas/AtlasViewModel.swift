import Foundation
import FlukeKit
import Observation

@MainActor
@Observable
public final class AtlasViewModel {
    public enum SubView: String, CaseIterable, Identifiable {
        case timeline = "Timeline"
        case range = "Range"
        case trace = "Trace"
        case predict = "Predict"

        public var id: String { rawValue }
    }

    public var activeSubView: SubView = .timeline
    public private(set) var catalogState: BrowseViewState<[Whale]> = .idle

    private let repository: any WhalesRepositoryProtocol
    private var loadGeneration = 0

    public init(
        repository: any WhalesRepositoryProtocol,
        activeSubView: SubView = .timeline
    ) {
        self.repository = repository
        self.activeSubView = activeSubView
    }

    public func loadCatalog() async {
        loadGeneration += 1
        let generation = loadGeneration
        catalogState = catalogState.beginRefresh()
        let result: BrowseResult<[Whale]>
        do {
            result = try await repository.loadCatalog()
        } catch {
            result = .failed(.unexpectedFeatureFailure)
        }
        guard generation == loadGeneration else { return }
        catalogState = .resolve(result)
    }

    public var catalog: [Whale] {
        catalogState.value ?? []
    }
}
