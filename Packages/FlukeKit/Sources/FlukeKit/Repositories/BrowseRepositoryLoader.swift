import Foundation

public struct BrowseRepositoryLoader: Sendable {
    private let cache: any BrowseCacheStore
    private let diagnostics: any BrowseCacheDiagnostics
    private let now: @Sendable () -> Date

    public init(
        cache: any BrowseCacheStore,
        diagnostics: any BrowseCacheDiagnostics = NoopBrowseCacheDiagnostics(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.cache = cache
        self.diagnostics = diagnostics
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
            try Task.checkCancellation()
            do {
                try await cache.replace(document, for: key)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                await diagnostics.record(BrowseCacheDiagnostic(
                    operation: .write,
                    resource: key.resource,
                    errorCode: cacheErrorCode(error)
                ))
            }
            try Task.checkCancellation()
            let metadata = BrowseMetadata(
                fetchedAt: document.fetchedAt,
                schemaVersion: document.schemaVersion
            )
            return isEmpty(value) ? .empty(metadata: metadata) : .fresh(value: value, metadata: metadata)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try await fallback(type, key: key, error: error, validate: validate)
        }
    }

    public func loadThenRefresh<Value: Codable & Sendable>(
        _ type: Value.Type,
        key: BrowseCacheKey,
        fetch: @escaping @Sendable () async throws -> Value,
        isEmpty: @escaping @Sendable (Value) -> Bool,
        validate: @escaping @Sendable (Value) throws -> Void
    ) -> AsyncThrowingStream<BrowseResult<Value>, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if let cached = try await cachedResult(type, key: key, validate: validate) {
                        continuation.yield(cached)
                    }
                    let refreshed = try await load(
                        type, key: key, fetch: fetch, isEmpty: isEmpty, validate: validate
                    )
                    continuation.yield(refreshed)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func cachedResult<Value: Codable & Sendable>(
        _ type: Value.Type,
        key: BrowseCacheKey,
        validate: @Sendable (Value) throws -> Void
    ) async throws -> BrowseResult<Value>? {
        try Task.checkCancellation()
        let document: BrowseCacheDocument<Value>?
        do {
            document = try await cache.load(type, for: key)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            await diagnostics.record(BrowseCacheDiagnostic(
                operation: .read,
                resource: key.resource,
                errorCode: cacheErrorCode(error)
            ))
            return nil
        }
        try Task.checkCancellation()
        guard let document else { return nil }
        if case .value(let value) = document.payload {
            do { try validate(value) } catch { return nil }
        }
        return .cached(
            payload: document.payload,
            metadata: BrowseMetadata(
                fetchedAt: document.fetchedAt,
                schemaVersion: document.schemaVersion
            )
        )
    }

    private func fallback<Value: Codable & Sendable>(
        _ type: Value.Type,
        key: BrowseCacheKey,
        error: Error,
        validate: @Sendable (Value) throws -> Void
    ) async throws -> BrowseResult<Value> {
        let failure = BrowseFailure(error: error)
        try Task.checkCancellation()
        let document: BrowseCacheDocument<Value>?
        do {
            document = try await cache.load(type, for: key)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            await diagnostics.record(BrowseCacheDiagnostic(
                operation: .read,
                resource: key.resource,
                errorCode: cacheErrorCode(error)
            ))
            return .failed(failure)
        }
        try Task.checkCancellation()
        guard let document else {
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
