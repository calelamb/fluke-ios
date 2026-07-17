import Foundation

public enum BrowseCacheError: Error, Equatable, Sendable {
    case corruptDocument
    case documentTooLarge
    case incompatibleSchema
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
    key: BrowseCacheKey
) throws -> BrowseCacheDocument<Value> {
    guard document.schemaVersion == BrowseCacheDocument<Value>.currentSchemaVersion else {
        throw BrowseCacheError.incompatibleSchema
    }
    guard document.resource == key.resource else {
        throw BrowseCacheError.resourceMismatch
    }
    return document
}
