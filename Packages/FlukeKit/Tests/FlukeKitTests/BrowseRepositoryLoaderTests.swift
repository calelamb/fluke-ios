import Foundation
import Testing

@testable import FlukeKit

@Suite("Browse repository loader")
struct BrowseRepositoryLoaderTests {
    private let now = Date(timeIntervalSince1970: 2_000)

    @Test("Successful network data is fresh and replaces the cache")
    func freshNetworkResult() async throws {
        let cache = MemoryBrowseCacheStore()
        let loader = BrowseRepositoryLoader(cache: cache, now: { now })
        let key = BrowseCacheKey(resource: "whales", identity: "catalog")

        let result = try await loader.load(
            [String].self,
            key: key,
            fetch: { ["J35"] },
            isEmpty: { $0.isEmpty },
            validate: { _ in }
        )

        guard case .fresh(let value, let metadata) = result else {
            Issue.record("Expected fresh data")
            return
        }
        #expect(value == ["J35"])
        #expect(metadata.fetchedAt == now)
        #expect(try await cache.load([String].self, for: key)?.payload == .value(["J35"]))
    }

    @Test("A successful empty response replaces older nonempty data")
    func trueEmpty() async throws {
        let cache = MemoryBrowseCacheStore()
        let key = BrowseCacheKey(resource: "sightings", identity: "approved")
        try await seed(["old"], in: cache, key: key)
        let loader = BrowseRepositoryLoader(cache: cache, now: { now })

        let result = try await loader.load(
            [String].self,
            key: key,
            fetch: { [] },
            isEmpty: { $0.isEmpty },
            validate: { _ in }
        )

        guard case .empty(let metadata) = result else {
            Issue.record("Expected a true empty result")
            return
        }
        #expect(metadata.fetchedAt == now)
        #expect(try await cache.load([String].self, for: key)?.payload == .empty)
    }

    @Test("Definite offline failure returns the cached payload")
    func cachedOffline() async throws {
        let cache = MemoryBrowseCacheStore()
        let key = BrowseCacheKey(resource: "whales", identity: "catalog")
        try await seed(["cached"], in: cache, key: key)
        let loader = BrowseRepositoryLoader(cache: cache, now: { now })

        let result = try await loader.load(
            [String].self,
            key: key,
            fetch: { throw APIError.offline },
            isEmpty: { $0.isEmpty },
            validate: { _ in }
        )

        guard case .cachedOffline(let payload, _) = result else {
            Issue.record("Expected cached offline data")
            return
        }
        #expect(payload == .value(["cached"]))
    }

    @Test("Online refresh failure returns stale cache with a safe failure")
    func staleCache() async throws {
        let cache = MemoryBrowseCacheStore()
        let key = BrowseCacheKey(resource: "whales", identity: "catalog")
        try await seed(["cached"], in: cache, key: key)
        let loader = BrowseRepositoryLoader(cache: cache, now: { now })

        let result = try await loader.load(
            [String].self,
            key: key,
            fetch: { throw APIError.timeout },
            isEmpty: { $0.isEmpty },
            validate: { _ in }
        )

        guard case .stale(let payload, _, let failure) = result else {
            Issue.record("Expected stale data")
            return
        }
        #expect(payload == .value(["cached"]))
        #expect(failure.code == "TIMEOUT")
        #expect(failure.retryable)
    }

    @Test("Failure without a valid cache stays failed rather than empty")
    func failedWithoutCache() async throws {
        let cache = MemoryBrowseCacheStore()
        let loader = BrowseRepositoryLoader(cache: cache, now: { now })

        let result = try await loader.load(
            [String].self,
            key: BrowseCacheKey(resource: "whales", identity: "catalog"),
            fetch: { throw APIError.timeout },
            isEmpty: { $0.isEmpty },
            validate: { _ in }
        )

        guard case .failed(let failure) = result else {
            Issue.record("Expected failure")
            return
        }
        #expect(failure.code == "TIMEOUT")
    }

    @Test("Cancellation is propagated and never replaces last known good")
    func cancellationPreservesCache() async throws {
        let cache = MemoryBrowseCacheStore()
        let key = BrowseCacheKey(resource: "whales", identity: "catalog")
        try await seed(["old"], in: cache, key: key)
        let loader = BrowseRepositoryLoader(cache: cache, now: { now })

        await #expect(throws: CancellationError.self) {
            try await loader.load(
                [String].self,
                key: key,
                fetch: { throw CancellationError() },
                isEmpty: { $0.isEmpty },
                validate: { _ in }
            )
        }
        #expect(try await cache.load([String].self, for: key)?.payload == .value(["old"]))
    }

    @Test("A cache write failure is diagnosed without hiding valid network data")
    func diagnosesWriteFailure() async throws {
        let diagnostics = DiagnosticRecorder()
        let loader = BrowseRepositoryLoader(
            cache: FailingBrowseCacheStore(failure: .write),
            diagnostics: diagnostics,
            now: { now }
        )

        let result = try await loader.load(
            [String].self,
            key: BrowseCacheKey(resource: "whales", identity: "catalog"),
            fetch: { ["fresh"] },
            isEmpty: { $0.isEmpty },
            validate: { _ in }
        )

        guard case .fresh(let values, _) = result else {
            Issue.record("Expected valid network data")
            return
        }
        #expect(values == ["fresh"])
        #expect(await diagnostics.events == [
            BrowseCacheDiagnostic(operation: .write, resource: "whales", errorCode: "ioFailure"),
        ])
    }

    @Test("A cache read failure is diagnosed before returning failed")
    func diagnosesReadFailure() async throws {
        let diagnostics = DiagnosticRecorder()
        let loader = BrowseRepositoryLoader(
            cache: FailingBrowseCacheStore(failure: .read),
            diagnostics: diagnostics,
            now: { now }
        )

        let result = try await loader.load(
            [String].self,
            key: BrowseCacheKey(resource: "sightings", identity: "approved"),
            fetch: { throw APIError.offline },
            isEmpty: { $0.isEmpty },
            validate: { _ in }
        )

        guard case .failed = result else {
            Issue.record("Expected failure without a readable cache")
            return
        }
        #expect(await diagnostics.events == [
            BrowseCacheDiagnostic(operation: .read, resource: "sightings", errorCode: "ioFailure"),
        ])
    }

    @Test("Cache cancellation is propagated rather than converted to a result")
    func propagatesCacheCancellation() async {
        let key = BrowseCacheKey(resource: "whales", identity: "catalog")
        await #expect(throws: CancellationError.self) {
            try await BrowseRepositoryLoader(
                cache: FailingBrowseCacheStore(failure: .writeCancellation)
            ).load(
                [String].self,
                key: key,
                fetch: { ["fresh"] },
                isEmpty: { $0.isEmpty },
                validate: { _ in }
            )
        }
        await #expect(throws: CancellationError.self) {
            try await BrowseRepositoryLoader(
                cache: FailingBrowseCacheStore(failure: .readCancellation)
            ).load(
                [String].self,
                key: key,
                fetch: { throw APIError.offline },
                isEmpty: { $0.isEmpty },
                validate: { _ in }
            )
        }
    }

    private func seed(
        _ value: [String],
        in cache: MemoryBrowseCacheStore,
        key: BrowseCacheKey
    ) async throws {
        try await cache.replace(
            BrowseCacheDocument(
                resource: key.resource,
                fetchedAt: Date(timeIntervalSince1970: 1_000),
                payload: .value(value)
            ),
            for: key
        )
    }
}

private enum InjectedCacheFailure: Error, Equatable {
    case read
    case write
    case readCancellation
    case writeCancellation
}

private actor FailingBrowseCacheStore: BrowseCacheStore {
    let failure: InjectedCacheFailure

    init(failure: InjectedCacheFailure) {
        self.failure = failure
    }

    func load<Value: Codable & Sendable>(
        _ type: Value.Type,
        for key: BrowseCacheKey
    ) throws -> BrowseCacheDocument<Value>? {
        if failure == .read { throw InjectedCacheFailure.read }
        if failure == .readCancellation { throw CancellationError() }
        return nil
    }

    func replace<Value: Codable & Sendable>(
        _ document: BrowseCacheDocument<Value>,
        for key: BrowseCacheKey
    ) throws {
        if failure == .write { throw InjectedCacheFailure.write }
        if failure == .writeCancellation { throw CancellationError() }
    }

    func remove(_ key: BrowseCacheKey) {}
}

private actor DiagnosticRecorder: BrowseCacheDiagnostics {
    private(set) var events: [BrowseCacheDiagnostic] = []

    func record(_ diagnostic: BrowseCacheDiagnostic) {
        events = events + [diagnostic]
    }
}
