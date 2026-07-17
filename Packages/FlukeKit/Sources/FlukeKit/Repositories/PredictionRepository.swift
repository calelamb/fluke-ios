import Foundation

public actor PredictionRepository: PredictionRepositoryProtocol {

    public enum Subject: Sendable {
        case whale(id: String)
        case pod(_ pod: Pod)

        var queryParam: String {
            switch self {
            case .whale(let id): return "whaleId=\(id)"
            case .pod(let pod): return "pod=\(pod.rawValue)"
            }
        }
    }

    private let api: APIClient
    private let loader: BrowseRepositoryLoader

    public init(api: APIClient, cache: any BrowseCacheStore = MemoryBrowseCacheStore()) {
        self.api = api
        self.loader = BrowseRepositoryLoader(cache: cache)
    }

    public func load(
        subject: Subject,
        horizon: PredictionHorizon
    ) async throws -> BrowseResult<Prediction?> {
        let key = "\(subject.queryParam)|\(horizon.rawValue)"
        return try await loader.load(
            Prediction?.self,
            key: BrowseCacheKey(resource: "prediction", identity: key),
            fetch: { [api] in try await Self.request(api: api, subject: subject, horizon: horizon) },
            isEmpty: { $0 == nil },
            validate: { prediction in
                if let prediction { try PublicBrowseValidator.prediction(prediction) }
            }
        )
    }

    public func fetch(subject: Subject, horizon: PredictionHorizon) async throws -> Prediction? {
        let prediction = try await Self.request(api: api, subject: subject, horizon: horizon)
        if let prediction { try PublicBrowseValidator.prediction(prediction) }
        return prediction
    }

    private static func request(
        api: APIClient,
        subject: Subject,
        horizon: PredictionHorizon
    ) async throws -> Prediction? {
        do {
            let path = "\(Endpoint.predict)?\(subject.queryParam)&horizon=\(horizon.rawValue)"
            return try await api.get(path)
        } catch APIError.remote(status: 404, code: _, message: _, retryable: _, requestId: _) {
            return nil
        }
    }
}
