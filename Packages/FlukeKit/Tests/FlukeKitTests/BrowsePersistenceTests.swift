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

    @Test("Cache pruning removes oversized files without retaining them as entries")
    func pruningRemovesOversizedFile() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let oversizedKey = BrowseCacheKey(resource: "whales", identity: "oversized")
        let oversizedURL = directory.appendingPathComponent(oversizedKey.filename)
        let oversized = BrowseCacheDocument(
            resource: oversizedKey.resource,
            fetchedAt: Date(timeIntervalSince1970: 1),
            payload: BrowsePayload.value([String(repeating: "x", count: 1_000)])
        )
        try JSONEncoder.fluke.encode(oversized).write(to: oversizedURL)
        let store = FileBrowseCacheStore(
            directory: directory,
            maxDocumentBytes: 512,
            maxEntryCount: 64,
            maxTotalBytes: 10_000
        )
        let safeKey = BrowseCacheKey(resource: "sightings", identity: "safe")

        try await seedFile(["safe"], key: safeKey, fetchedAt: 2, store: store)

        #expect(!FileManager.default.fileExists(atPath: oversizedURL.path))
        #expect(try await store.load([String].self, for: safeKey) != nil)
    }

    @Test("File cache enforces its entry limit by evicting the oldest document")
    func enforcesEntryLimit() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileBrowseCacheStore(
            directory: directory,
            maxEntryCount: 2,
            maxTotalBytes: 10_000
        )
        let keys = (1...3).map { BrowseCacheKey(resource: "whale-profile", identity: "whale-\($0)") }
        for (index, key) in keys.enumerated() {
            try await store.replace(
                BrowseCacheDocument(
                    resource: key.resource,
                    fetchedAt: Date(timeIntervalSince1970: Double(index + 1)),
                    payload: BrowsePayload.value(["whale-\(index + 1)"])
                ),
                for: key
            )
        }

        #expect(try await store.load([String].self, for: keys[0]) == nil)
        #expect(try await store.load([String].self, for: keys[1]) != nil)
        #expect(try await store.load([String].self, for: keys[2]) != nil)
    }

    @Test("Optional identity caches are evicted before core browse snapshots")
    func preservesCoreResources() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileBrowseCacheStore(
            directory: directory,
            maxEntryCount: 2,
            maxTotalBytes: 10_000
        )
        let catalog = BrowseCacheKey(resource: "whales", identity: "catalog")
        let profile = BrowseCacheKey(resource: "whale-profile", identity: "whale-1")
        let sightings = BrowseCacheKey(resource: "sightings", identity: "approved")
        try await seedFile(["catalog"], key: catalog, fetchedAt: 1, store: store)
        try await seedFile(["profile"], key: profile, fetchedAt: 2, store: store)
        try await seedFile(["sightings"], key: sightings, fetchedAt: 3, store: store)

        #expect(try await store.load([String].self, for: catalog) != nil)
        #expect(try await store.load([String].self, for: profile) == nil)
        #expect(try await store.load([String].self, for: sightings) != nil)
    }

    @Test("File cache enforces its total byte limit")
    func enforcesTotalByteLimit() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileBrowseCacheStore(
            directory: directory,
            maxDocumentBytes: 1_024,
            maxEntryCount: 64,
            maxTotalBytes: 450
        )
        for index in 1...3 {
            let key = BrowseCacheKey(resource: "whale-profile", identity: "whale-\(index)")
            try await seedFile(
                [String(repeating: Character(String(index)), count: 100)],
                key: key,
                fetchedAt: Double(index),
                store: store
            )
        }

        let total = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        ).reduce(0) { partial, url in
            partial + (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        }
        #expect(total <= 450)
    }

    @Test("Old schema, corrupt, and future cache documents are deleted")
    func deletesUnsafeDocuments() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 10_000)
        let store = FileBrowseCacheStore(directory: directory, now: { now })

        let oldKey = BrowseCacheKey(resource: "whales", identity: "old")
        try rawDocument(schema: 0, fetchedAt: now, key: oldKey).write(to: directory.appendingPathComponent(oldKey.filename))
        await #expect(throws: BrowseCacheError.obsoleteSchema) {
            try await store.load([String].self, for: oldKey)
        }
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(oldKey.filename).path))

        let futureKey = BrowseCacheKey(resource: "whales", identity: "future")
        try rawDocument(schema: 1, fetchedAt: now.addingTimeInterval(600), key: futureKey)
            .write(to: directory.appendingPathComponent(futureKey.filename))
        await #expect(throws: BrowseCacheError.invalidFetchedAt) {
            try await store.load([String].self, for: futureKey)
        }
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(futureKey.filename).path))

        let corruptKey = BrowseCacheKey(resource: "whales", identity: "corrupt")
        try Data("not-json".utf8).write(to: directory.appendingPathComponent(corruptKey.filename))
        await #expect(throws: BrowseCacheError.corruptDocument) {
            try await store.load([String].self, for: corruptKey)
        }
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(corruptKey.filename).path))
    }

    @Test("Unknown newer cache schema is preserved for a future app version")
    func preservesNewerSchema() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = BrowseCacheKey(resource: "whales", identity: "newer")
        let url = directory.appendingPathComponent(key.filename)
        let bytes = rawDocument(schema: 2, fetchedAt: Date(), key: key)
        try bytes.write(to: url)
        let store = FileBrowseCacheStore(directory: directory)

        await #expect(throws: BrowseCacheError.newerSchema) {
            try await store.load([String].self, for: key)
        }
        #expect(try Data(contentsOf: url) == bytes)
    }

    @Test("Newer schema files do not consume the active schema cache quota")
    func newerSchemaDoesNotConsumeActiveQuota() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let newerKey = BrowseCacheKey(resource: "whales", identity: "newer")
        let newerURL = directory.appendingPathComponent(newerKey.filename)
        let newerBytes = rawDocument(schema: 2, fetchedAt: Date(), key: newerKey)
        try newerBytes.write(to: newerURL)
        let store = FileBrowseCacheStore(
            directory: directory,
            maxEntryCount: 2,
            maxTotalBytes: 10_000
        )
        let first = BrowseCacheKey(resource: "whales", identity: "first")
        let second = BrowseCacheKey(resource: "sightings", identity: "second")

        try await seedFile(["first"], key: first, fetchedAt: 1, store: store)
        try await seedFile(["second"], key: second, fetchedAt: 2, store: store)

        #expect(try await store.load([String].self, for: first) != nil)
        #expect(try await store.load([String].self, for: second) != nil)
        #expect(try Data(contentsOf: newerURL) == newerBytes)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func seedFile(
        _ value: [String],
        key: BrowseCacheKey,
        fetchedAt: Double,
        store: FileBrowseCacheStore
    ) async throws {
        try await store.replace(
            BrowseCacheDocument(
                resource: key.resource,
                fetchedAt: Date(timeIntervalSince1970: fetchedAt),
                payload: BrowsePayload.value(value)
            ),
            for: key
        )
    }

    private func rawDocument(schema: Int, fetchedAt: Date, key: BrowseCacheKey) -> Data {
        try! JSONEncoder.fluke.encode(
            BrowseCacheDocument(
                schemaVersion: schema,
                resource: key.resource,
                fetchedAt: fetchedAt,
                payload: BrowsePayload.value(["cached"])
            )
        )
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
