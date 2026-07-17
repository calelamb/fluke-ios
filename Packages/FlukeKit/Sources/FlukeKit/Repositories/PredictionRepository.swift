import Foundation

public actor PredictionRepository: PredictionRepositoryProtocol {

    public enum Subject: Sendable {
        case whale(id: String)
        case pod(_ pod: Pod)

        var queryItem: URLQueryItem {
            switch self {
            case .whale(let id): URLQueryItem(name: "whaleId", value: id)
            case .pod(let pod): URLQueryItem(name: "pod", value: pod.rawValue)
            }
        }

        var identity: String {
            switch self {
            case .whale(let id): "whaleId=\(id)"
            case .pod(let pod): "pod=\(pod.rawValue)"
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
        if case .whale(let id) = subject { try BrowseRequestValidator.identifier(id) }
        let key = "\(subject.identity)|\(horizon.rawValue)"
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
        if case .whale(let id) = subject { try BrowseRequestValidator.identifier(id) }
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
            return try await api.get(APIRequest(
                path: Endpoint.predict,
                queryItems: [
                    subject.queryItem,
                    URLQueryItem(name: "horizon", value: horizon.rawValue),
                ]
            ))
        } catch APIError.remote(status: 404, code: _, message: _, retryable: _, requestId: _) {
            return nil
        }
    }
}
