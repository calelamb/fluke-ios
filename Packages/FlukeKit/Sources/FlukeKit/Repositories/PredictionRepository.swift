import Foundation

public actor PredictionRepository {

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
    private var cache: [String: (Date, Prediction)] = [:]

    public init(api: APIClient) {
        self.api = api
    }

    public func fetch(subject: Subject, horizon: PredictionHorizon) async throws -> Prediction? {
        let key = "\(subject.queryParam)|\(horizon.rawValue)"
        if let entry = cache[key],
           Date().timeIntervalSince(entry.0) < 86400 {
            return entry.1
        }
        do {
            let path = "\(Endpoint.predict)?\(subject.queryParam)&horizon=\(horizon.rawValue)"
            let prediction: Prediction = try await api.get(path)
            cache[key] = (Date(), prediction)
            return prediction
        } catch APIError.server(status: 404, body: _) {
            return nil
        }
    }
}
