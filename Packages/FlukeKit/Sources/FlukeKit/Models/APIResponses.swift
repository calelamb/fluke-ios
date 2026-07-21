import Foundation

public enum HealthStatus: String, Codable, Sendable {
    case ok
}

public struct HealthResponse: Codable, Hashable, Sendable {
    public let status: HealthStatus
    public let timestamp: Date
}

public enum IdentificationMode: String, Codable, Hashable, Sendable {
    case disabled
    case onDevice = "on-device"
    case server
}

public struct Capabilities: Codable, Hashable, Sendable {
    public let accounts: Bool
    public let identification: Bool
    public let identificationMode: IdentificationMode
    public let submissions: Bool

    private enum CodingKeys: String, CodingKey {
        case accounts
        case identification
        case identificationMode
        case submissions
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        accounts = try values.decode(Bool.self, forKey: .accounts)
        identification = try values.decode(Bool.self, forKey: .identification)
        identificationMode = try values.decodeIfPresent(
            IdentificationMode.self,
            forKey: .identificationMode
        ) ?? (identification ? .server : .disabled)
        submissions = try values.decode(Bool.self, forKey: .submissions)
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(accounts, forKey: .accounts)
        try values.encode(identification, forKey: .identification)
        try values.encode(identificationMode, forKey: .identificationMode)
        try values.encode(submissions, forKey: .submissions)
    }
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
