import Foundation

public struct BrowseMetadata: Equatable, Sendable {
    public let fetchedAt: Date
    public let schemaVersion: Int

    public init(fetchedAt: Date, schemaVersion: Int) {
        self.fetchedAt = fetchedAt
        self.schemaVersion = schemaVersion
    }
}

public struct BrowseFailure: Error, Equatable, Sendable {
    public let code: String
    public let message: String
    public let retryable: Bool
    public let requestId: String?

    public init(code: String, message: String, retryable: Bool, requestId: String?) {
        self.code = code
        self.message = message
        self.retryable = retryable
        self.requestId = requestId
    }

    init(error: Error) {
        guard let api = error as? APIError else {
            self.init(
                code: "REQUEST_FAILED",
                message: "Fluke couldn't complete the request.",
                retryable: false,
                requestId: nil
            )
            return
        }
        switch api {
        case .remote(_, let code, let message, let retryable, let requestId):
            self.init(code: code, message: message, retryable: retryable, requestId: requestId)
        case .timeout:
            self.init(code: "TIMEOUT", message: api.localizedDescription, retryable: true, requestId: nil)
        case .offline:
            self.init(code: "OFFLINE", message: api.localizedDescription, retryable: true, requestId: nil)
        case .transport:
            self.init(code: "TRANSPORT", message: api.localizedDescription, retryable: true, requestId: nil)
        case .unauthorized:
            self.init(code: "UNAUTHORIZED", message: api.localizedDescription, retryable: false, requestId: nil)
        case .decoding, .invalidPagination, .malformedResponse:
            self.init(code: "INVALID_RESPONSE", message: api.localizedDescription, retryable: false, requestId: nil)
        }
    }
}

public enum BrowseResult<Value: Codable & Sendable>: Sendable {
    case fresh(value: Value, metadata: BrowseMetadata)
    case empty(metadata: BrowseMetadata)
    case stale(
        payload: BrowsePayload<Value>,
        metadata: BrowseMetadata,
        failure: BrowseFailure
    )
    case cachedOffline(payload: BrowsePayload<Value>, metadata: BrowseMetadata)
    case failed(BrowseFailure)
}

extension BrowseResult: Equatable where Value: Equatable {}
