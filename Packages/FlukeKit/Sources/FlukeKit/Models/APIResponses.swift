import Foundation

public enum HealthStatus: String, Codable, Sendable {
    case ok
}

public struct HealthResponse: Codable, Hashable, Sendable {
    public let status: HealthStatus
    public let timestamp: Date
}

public struct Capabilities: Codable, Hashable, Sendable {
    public let accounts: Bool
    public let identification: Bool
    public let submissions: Bool
}

public struct PageMetadata: Codable, Hashable, Sendable {
    public let hasMore: Bool
    public let nextCursor: String?
}

public struct PaginatedResponse<Item: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    public let items: [Item]
    public let page: PageMetadata
}

public struct SafeError: Codable, Hashable, Sendable {
    public let code: String
    public let message: String
    public let requestId: String
    public let retryable: Bool
}
