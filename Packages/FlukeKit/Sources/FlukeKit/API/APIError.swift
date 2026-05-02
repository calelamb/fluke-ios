import Foundation

/// A typed error returned by `APIClient`. Carries enough context for both
/// developer-facing logging and user-facing messages.
public enum APIError: LocalizedError, Equatable {
    case network(Error)
    case unauthorized
    case server(status: Int, body: String)
    case decoding(_ typeName: String)
    case unknown

    public var errorDescription: String? {
        switch self {
        case .network(let underlying):
            return "Network problem — \(underlying.localizedDescription)"
        case .unauthorized:
            return "You're not signed in."
        case .server(let status, let body):
            return "Server error \(status): \(body)"
        case .decoding(let type):
            return "Couldn't read the server's response (\(type))."
        case .unknown:
            return "Something unexpected went wrong."
        }
    }

    public static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.unauthorized, .unauthorized), (.unknown, .unknown):
            return true
        case let (.server(s1, b1), .server(s2, b2)):
            return s1 == s2 && b1 == b2
        case let (.decoding(t1), .decoding(t2)):
            return t1 == t2
        case let (.network(e1), .network(e2)):
            return (e1 as NSError) == (e2 as NSError)
        default:
            return false
        }
    }
}
