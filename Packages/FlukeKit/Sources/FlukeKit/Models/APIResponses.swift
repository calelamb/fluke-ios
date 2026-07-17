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

public struct SafeError: Codable, Hashable, Sendable {
    public let error: String
}
