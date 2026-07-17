import Foundation

public actor FileBrowseCacheStore: BrowseCacheStore {
    public static let defaultMaxDocumentBytes = 20 * 1_024 * 1_024
    public static let defaultMaxEntryCount = 64
    public static let defaultMaxTotalBytes = 100 * 1_024 * 1_024

    private let directory: URL
    private let writer: any AtomicDataWriting
    private let diagnostics: any BrowseCacheDiagnostics
    private let maxDocumentBytes: Int
    private let maxEntryCount: Int
    private let maxTotalBytes: Int
    private let fileManager: FileManager
    private let now: @Sendable () -> Date

    public init(
        directory: URL,
        maxDocumentBytes: Int = FileBrowseCacheStore.defaultMaxDocumentBytes,
        maxEntryCount: Int = FileBrowseCacheStore.defaultMaxEntryCount,
        maxTotalBytes: Int = FileBrowseCacheStore.defaultMaxTotalBytes,
        diagnostics: any BrowseCacheDiagnostics = SystemBrowseCacheDiagnostics(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.init(
            directory: directory,
            writer: FoundationAtomicDataWriter(),
            maxDocumentBytes: maxDocumentBytes,
            maxEntryCount: maxEntryCount,
            maxTotalBytes: maxTotalBytes,
            diagnostics: diagnostics,
            now: now
        )
    }

    init(
        directory: URL,
        writer: any AtomicDataWriting,
        maxDocumentBytes: Int = FileBrowseCacheStore.defaultMaxDocumentBytes,
        maxEntryCount: Int = FileBrowseCacheStore.defaultMaxEntryCount,
        maxTotalBytes: Int = FileBrowseCacheStore.defaultMaxTotalBytes,
        diagnostics: any BrowseCacheDiagnostics = NoopBrowseCacheDiagnostics(),
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.directory = directory
        self.writer = writer
        self.maxDocumentBytes = maxDocumentBytes
        self.maxEntryCount = maxEntryCount
        self.maxTotalBytes = maxTotalBytes
        self.diagnostics = diagnostics
        self.fileManager = fileManager
        self.now = now
    }

    public static func liveDirectory() -> URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("app.fluke", isDirectory: true)
            .appendingPathComponent("browse-cache", isDirectory: true)
    }

    public func load<Value: Codable & Sendable>(
        _ type: Value.Type,
        for key: BrowseCacheKey
    ) async throws -> BrowseCacheDocument<Value>? {
        let url = fileURL(for: key)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try boundedData(at: url)
            let document = try JSONDecoder.fluke.decode(BrowseCacheDocument<Value>.self, from: data)
            return try validatedDocument(document, key: key, now: now())
        } catch let error as BrowseCacheError {
            await record(.read, key: key, error: error)
            if error != .newerSchema { try? fileManager.removeItem(at: url) }
            throw error
        } catch {
            await record(.read, key: key, error: error)
            try? fileManager.removeItem(at: url)
            throw BrowseCacheError.corruptDocument
        }
    }

    public func replace<Value: Codable & Sendable>(
        _ document: BrowseCacheDocument<Value>,
        for key: BrowseCacheKey
    ) async throws {
        do {
            _ = try validatedDocument(document, key: key, now: now())
            let data = try JSONEncoder.fluke.encode(document)
            guard data.count <= maxDocumentBytes else {
                throw BrowseCacheError.documentTooLarge
            }
            try prepareDirectory()
            try await writer.write(data, to: fileURL(for: key))
            try await pruneIfNeeded()
        } catch {
            await record(.write, key: key, error: error)
            throw error
        }
    }

    public func remove(_ key: BrowseCacheKey) throws {
        let url = fileURL(for: key)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private func boundedData(at url: URL) throws -> Data {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        if let size = attributes[.size] as? NSNumber, size.intValue > maxDocumentBytes {
            throw BrowseCacheError.documentTooLarge
        }
        let data = try Data(contentsOf: url)
        guard data.count <= maxDocumentBytes else { throw BrowseCacheError.documentTooLarge }
        return data
    }

    private func pruneIfNeeded() async throws {
        var entries = try cacheEntries().filter { !$0.isNewerSchema }
        var totalBytes = entries.reduce(0) { $0 + $1.byteCount }
        let sorted = entries.sorted { lhs, rhs in
            if lhs.isOptional != rhs.isOptional { return lhs.isOptional }
            return lhs.fetchedAt < rhs.fetchedAt
        }
        var candidates = sorted[...]
        while entries.count > maxEntryCount || totalBytes > maxTotalBytes {
            guard let entry = candidates.popFirst() else { break }
            do {
                try fileManager.removeItem(at: entry.url)
                entries.removeAll { $0.url == entry.url }
                totalBytes -= entry.byteCount
            } catch {
                await diagnostics.record(BrowseCacheDiagnostic(
                    operation: .prune,
                    resource: entry.resource,
                    errorCode: cacheErrorCode(error)
                ))
                throw error
            }
        }
    }

    private func cacheEntries() throws -> [CacheEntry] {
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "json" }
        return urls.compactMap { url in
            guard let byteCount = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  byteCount <= maxDocumentBytes else {
                try? fileManager.removeItem(at: url)
                return nil
            }
            guard let data = try? Data(contentsOf: url),
                  data.count <= maxDocumentBytes,
                  let header = try? JSONDecoder.fluke.decode(CacheHeader.self, from: data) else {
                try? fileManager.removeItem(at: url)
                return nil
            }
            let isNewer = header.schemaVersion > BrowseCacheDocument<String>.currentSchemaVersion
            if !isNewer,
               (header.schemaVersion < BrowseCacheDocument<String>.currentSchemaVersion
                || !header.fetchedAt.timeIntervalSinceReferenceDate.isFinite
                || header.fetchedAt > now().addingTimeInterval(300)) {
                try? fileManager.removeItem(at: url)
                return nil
            }
            return CacheEntry(
                url: url,
                byteCount: byteCount,
                resource: header.resource,
                fetchedAt: header.fetchedAt,
                isNewerSchema: isNewer
            )
        }
    }

    private func record(_ operation: BrowseCacheOperation, key: BrowseCacheKey, error: Error) async {
        await diagnostics.record(BrowseCacheDiagnostic(
            operation: operation,
            resource: key.resource,
            errorCode: cacheErrorCode(error)
        ))
    }

    private func fileURL(for key: BrowseCacheKey) -> URL {
        directory.appendingPathComponent(key.filename, isDirectory: false)
    }

    private func prepareDirectory() throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = directory
        try mutableDirectory.setResourceValues(values)
    }
}

private struct CacheHeader: Decodable {
    let schemaVersion: Int
    let resource: String
    let fetchedAt: Date
}

private struct CacheEntry {
    let url: URL
    let byteCount: Int
    let resource: String
    let fetchedAt: Date
    let isNewerSchema: Bool

    var isOptional: Bool {
        resource == "whale-profile" || resource == "whale-track" || resource == "prediction"
    }
}
