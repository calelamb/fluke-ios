import Foundation

public enum BrowseCacheError: Error, Equatable, Sendable {
    case corruptDocument
    case documentTooLarge
    case obsoleteSchema
    case newerSchema
    case invalidFetchedAt
    case resourceMismatch
}

public protocol BrowseCacheStore: Sendable {
    func load<Value: Codable & Sendable>(
        _ type: Value.Type,
        for key: BrowseCacheKey
    ) async throws -> BrowseCacheDocument<Value>?

    func replace<Value: Codable & Sendable>(
        _ document: BrowseCacheDocument<Value>,
        for key: BrowseCacheKey
    ) async throws

    func remove(_ key: BrowseCacheKey) async throws
}

protocol AtomicDataWriting: Sendable {
    func write(_ data: Data, to url: URL) async throws
}

struct FoundationAtomicDataWriter: AtomicDataWriting {
    func write(_ data: Data, to url: URL) async throws {
        try data.write(
            to: url,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }
}

func validatedDocument<Value: Codable & Sendable>(
    _ document: BrowseCacheDocument<Value>,
    key: BrowseCacheKey,
    now: Date = Date(),
    maximumFutureSkew: TimeInterval = 300
) throws -> BrowseCacheDocument<Value> {
    let current = BrowseCacheDocument<Value>.currentSchemaVersion
    guard document.schemaVersion >= current else {
        throw BrowseCacheError.obsoleteSchema
    }
    guard document.schemaVersion <= current else {
        throw BrowseCacheError.newerSchema
    }
    guard document.resource == key.resource else {
        throw BrowseCacheError.resourceMismatch
    }
    let timestamp = document.fetchedAt.timeIntervalSinceReferenceDate
    guard timestamp.isFinite,
          document.fetchedAt <= now.addingTimeInterval(maximumFutureSkew) else {
        throw BrowseCacheError.invalidFetchedAt
    }
    return document
}
