import Foundation

public enum BrowsePayload<Value: Codable & Sendable>: Codable, Sendable {
    case value(Value)
    case empty
}

extension BrowsePayload: Equatable where Value: Equatable {}

public struct BrowseCacheDocument<Value: Codable & Sendable>: Codable, Sendable {
    public static var currentSchemaVersion: Int { 1 }

    public let schemaVersion: Int
    public let resource: String
    public let fetchedAt: Date
    public let payload: BrowsePayload<Value>

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        resource: String,
        fetchedAt: Date,
        payload: BrowsePayload<Value>
    ) {
        self.schemaVersion = schemaVersion
        self.resource = resource
        self.fetchedAt = fetchedAt
        self.payload = payload
    }
}

extension BrowseCacheDocument: Equatable where Value: Equatable {}
