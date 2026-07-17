import Foundation

public actor MemoryBrowseCacheStore: BrowseCacheStore {
    private var documents: [BrowseCacheKey: Data] = [:]
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    public func load<Value: Codable & Sendable>(
        _ type: Value.Type,
        for key: BrowseCacheKey
    ) throws -> BrowseCacheDocument<Value>? {
        guard let data = documents[key] else { return nil }
        do {
            let document = try JSONDecoder.fluke.decode(BrowseCacheDocument<Value>.self, from: data)
            return try validatedDocument(document, key: key, now: now())
        } catch let error as BrowseCacheError {
            throw error
        } catch {
            throw BrowseCacheError.corruptDocument
        }
    }

    public func replace<Value: Codable & Sendable>(
        _ document: BrowseCacheDocument<Value>,
        for key: BrowseCacheKey
    ) throws {
        _ = try validatedDocument(document, key: key, now: now())
        documents = documents.merging([key: try JSONEncoder.fluke.encode(document)]) { _, new in new }
    }

    public func remove(_ key: BrowseCacheKey) {
        documents = documents.filter { $0.key != key }
    }
}
