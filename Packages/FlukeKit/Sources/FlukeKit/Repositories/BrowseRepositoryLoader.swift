import Foundation

public struct BrowseRepositoryLoader: Sendable {
    private let cache: any BrowseCacheStore
    private let now: @Sendable () -> Date

    public init(
        cache: any BrowseCacheStore,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.cache = cache
        self.now = now
    }

    public func load<Value: Codable & Sendable>(
        _ type: Value.Type,
        key: BrowseCacheKey,
        fetch: @escaping @Sendable () async throws -> Value,
        isEmpty: @escaping @Sendable (Value) -> Bool,
        validate: @escaping @Sendable (Value) throws -> Void
    ) async throws -> BrowseResult<Value> {
        do {
            let value = try await fetch()
            try validate(value)
            try Task.checkCancellation()
            let payload: BrowsePayload<Value> = isEmpty(value) ? .empty : .value(value)
            let document = BrowseCacheDocument(
                resource: key.resource,
                fetchedAt: now(),
                payload: payload
            )
            try? await cache.replace(document, for: key)
            let metadata = BrowseMetadata(
                fetchedAt: document.fetchedAt,
                schemaVersion: document.schemaVersion
            )
            return isEmpty(value) ? .empty(metadata: metadata) : .fresh(value: value, metadata: metadata)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return await fallback(type, key: key, error: error, validate: validate)
        }
    }

    private func fallback<Value: Codable & Sendable>(
        _ type: Value.Type,
        key: BrowseCacheKey,
        error: Error,
        validate: @Sendable (Value) throws -> Void
    ) async -> BrowseResult<Value> {
        let failure = BrowseFailure(error: error)
        guard let document = try? await cache.load(type, for: key) else {
            return .failed(failure)
        }
        if case .value(let value) = document.payload {
            do {
                try validate(value)
            } catch {
                return .failed(failure)
            }
        }
        let metadata = BrowseMetadata(
            fetchedAt: document.fetchedAt,
            schemaVersion: document.schemaVersion
        )
        if error as? APIError == .offline {
            return .cachedOffline(payload: document.payload, metadata: metadata)
        }
        return .stale(payload: document.payload, metadata: metadata, failure: failure)
    }
}
