import FlukeKit
import Observation

@MainActor
@Observable
public final class WhaleProfileViewModel {
    public let whale: Whale
    public private(set) var state: BrowseViewState<WhaleProfile?> = .idle

    private let repository: any WhalesRepositoryProtocol
    private var loadGeneration = 0

    public init(whale: Whale, repository: any WhalesRepositoryProtocol) {
        self.whale = whale
        self.repository = repository
    }

    public func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        state = state.beginRefresh()
        let result: BrowseResult<WhaleProfile?>
        do {
            result = try await repository.loadProfile(id: whale.id)
        } catch {
            result = .failed(.unexpectedFeatureFailure)
        }
        guard generation == loadGeneration else { return }
        state = .resolve(result)
    }

    public func retry() async {
        await load()
    }

    public var profile: WhaleProfile? {
        state.value ?? nil
    }

    public var isEmpty: Bool {
        if case .empty = state { return true }
        if case .content(nil, _, _) = state { return true }
        return false
    }
}
