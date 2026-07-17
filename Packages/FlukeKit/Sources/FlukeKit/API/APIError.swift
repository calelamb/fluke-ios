import Foundation

public enum APIError: LocalizedError, Equatable, Sendable {
    case unauthorized
    case remote(
        status: Int,
        code: String,
        message: String,
        retryable: Bool,
        requestId: String?
    )
    case decoding(String)
    case invalidRequest
    case invalidPagination
    case malformedResponse
    case timeout
    case offline
    case transport

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "You're not signed in."
        case .remote(_, _, let message, _, _):
            return message
        case .decoding:
            return "Fluke couldn't read the service response."
        case .invalidRequest:
            return "The request contains an invalid value."
        case .invalidPagination, .malformedResponse:
            return "Fluke received an invalid service response."
        case .timeout:
            return "The request took too long. Please try again."
        case .offline:
            return "You're offline."
        case .transport:
            return "Fluke couldn't reach the service."
        }
    }

    public var retryable: Bool {
        switch self {
        case .remote(_, _, _, let retryable, _): retryable
        case .timeout, .offline, .transport: true
        default: false
        }
    }
}
