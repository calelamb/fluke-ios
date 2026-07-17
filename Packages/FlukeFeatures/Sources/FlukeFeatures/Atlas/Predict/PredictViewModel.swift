import Foundation
import Observation
import FlukeKit

@MainActor
@Observable
public final class PredictViewModel {

    public enum Subject: Equatable {
        case whale(id: String)
        case pod(_ pod: Pod)
    }

    public private(set) var state: BrowseViewState<Prediction?> = .idle
    public var horizon: PredictionHorizon = .h24 {
        didSet {
            guard horizon != oldValue else { return }
            invalidateQueryState()
        }
    }
    public var subject: Subject? {
        didSet {
            guard subject != oldValue else { return }
            invalidateQueryState()
        }
    }

    private let predictions: any PredictionRepositoryProtocol
    private var loadGeneration = 0

    public init(repository: any PredictionRepositoryProtocol) {
        self.predictions = repository
    }

    public func loadIfNeeded() async {
        guard let subject else {
            state = .idle
            return
        }
        loadGeneration += 1
        let generation = loadGeneration
        state = state.beginRefresh()
        let mappedSubject: PredictionRepository.Subject = {
            switch subject {
            case .whale(let id): return .whale(id: id)
            case .pod(let pod): return .pod(pod)
            }
        }()
        let result: BrowseResult<Prediction?>
        do {
            result = try await predictions.load(subject: mappedSubject, horizon: horizon)
        } catch {
            result = .failed(.unexpectedFeatureFailure)
        }
        guard generation == loadGeneration else { return }
        state = .resolve(result)
    }

    public func retry() async { await loadIfNeeded() }

    public var prediction: Prediction? { state.value ?? nil }

    public var isEmpty: Bool {
        if case .empty = state { return true }
        if case .content(nil, _, _) = state { return true }
        return false
    }

    private func invalidateQueryState() {
        loadGeneration += 1
        state = .idle
    }
}
