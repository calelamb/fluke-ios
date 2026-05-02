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

    public enum LoadState {
        case idle
        case loading
        case loaded(Prediction)
        case empty(reason: String)
        case error(String)
    }

    public private(set) var loadState: LoadState = .idle
    public var horizon: PredictionHorizon = .h24
    public var subject: Subject? {
        didSet { Task { await loadIfNeeded() } }
    }

    private let predictions: PredictionRepository

    public init(repository: PredictionRepository) {
        self.predictions = repository
    }

    public func loadIfNeeded() async {
        guard let subject else {
            loadState = .idle
            return
        }
        loadState = .loading
        let mappedSubject: PredictionRepository.Subject = {
            switch subject {
            case .whale(let id): return .whale(id: id)
            case .pod(let pod): return .pod(pod)
            }
        }()
        do {
            if let p = try await predictions.fetch(subject: mappedSubject, horizon: horizon) {
                loadState = .loaded(p)
            } else {
                loadState = .empty(reason: "Not enough data to predict yet — try the Trace view first.")
            }
        } catch {
            loadState = .error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
