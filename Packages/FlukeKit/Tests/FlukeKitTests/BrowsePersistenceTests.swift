import Foundation
import Testing

@testable import FlukeKit

@Suite("Browse persistence")
struct BrowsePersistenceTests {
    @Test("Cache keys are stable and never expose request identifiers")
    func safeStableKey() {
        let first = BrowseCacheKey(resource: "whale-profile", identity: "whale/../../secret")
        let second = BrowseCacheKey(resource: "whale-profile", identity: "whale/../../secret")

        #expect(first == second)
        #expect(!first.filename.contains("secret"))
        #expect(!first.filename.contains(".."))
    }

    @Test("Memory cache round trips immutable versioned payloads")
    func memoryRoundTrip() async throws {
        let store = MemoryBrowseCacheStore()
        let key = BrowseCacheKey(resource: "whales", identity: "catalog")
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let document = BrowseCacheDocument(
            resource: key.resource,
            fetchedAt: fetchedAt,
            payload: BrowsePayload.value(["J35", "L25"])
        )

        try await store.replace(document, for: key)
        let loaded = try await store.load([String].self, for: key)

        #expect(loaded == document)
    }

    @Test("A failed atomic replacement preserves the last known good bytes")
    func failedReplacementPreservesOldValue() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = FailOnSecondWrite()
        let store = FileBrowseCacheStore(directory: directory, writer: writer)
        let key = BrowseCacheKey(resource: "whales", identity: "catalog")
        let old = BrowseCacheDocument(
            resource: key.resource,
            fetchedAt: Date(timeIntervalSince1970: 100),
            payload: BrowsePayload.value(["old"])
        )
        let replacement = BrowseCacheDocument(
            resource: key.resource,
            fetchedAt: Date(timeIntervalSince1970: 200),
            payload: BrowsePayload.value(["new"])
        )
        try await store.replace(old, for: key)

        await #expect(throws: AtomicWriterFailure.injected) {
            try await store.replace(replacement, for: key)
        }

        let loaded = try await store.load([String].self, for: key)
        #expect(loaded == old)
    }

    @Test("Documents above the configured bound never replace cached data")
    func rejectsOversizedDocument() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileBrowseCacheStore(directory: directory, maxDocumentBytes: 128)
        let key = BrowseCacheKey(resource: "sightings", identity: "approved")
        let old = BrowseCacheDocument(
            resource: key.resource,
            fetchedAt: Date(timeIntervalSince1970: 100),
            payload: BrowsePayload.value(["old"])
        )
        try await store.replace(old, for: key)

        await #expect(throws: BrowseCacheError.documentTooLarge) {
            try await store.replace(
                BrowseCacheDocument(
                    resource: key.resource,
                    fetchedAt: Date(timeIntervalSince1970: 200),
                    payload: BrowsePayload.value([String(repeating: "x", count: 1_000)])
                ),
                for: key
            )
        }
        #expect(try await store.load([String].self, for: key) == old)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private enum AtomicWriterFailure: Error {
    case injected
}

private actor FailOnSecondWrite: AtomicDataWriting {
    private var writes = 0

    func write(_ data: Data, to url: URL) async throws {
        writes += 1
        guard writes < 2 else { throw AtomicWriterFailure.injected }
        try data.write(to: url, options: .atomic)
    }
}
