import Foundation

public actor FileBrowseCacheStore: BrowseCacheStore {
    public static let defaultMaxDocumentBytes = 20 * 1_024 * 1_024

    private let directory: URL
    private let writer: any AtomicDataWriting
    private let maxDocumentBytes: Int
    private let fileManager: FileManager

    public init(
        directory: URL,
        maxDocumentBytes: Int = FileBrowseCacheStore.defaultMaxDocumentBytes
    ) {
        self.init(
            directory: directory,
            writer: FoundationAtomicDataWriter(),
            maxDocumentBytes: maxDocumentBytes
        )
    }

    init(
        directory: URL,
        writer: any AtomicDataWriting,
        maxDocumentBytes: Int = FileBrowseCacheStore.defaultMaxDocumentBytes,
        fileManager: FileManager = .default
    ) {
        self.directory = directory
        self.writer = writer
        self.maxDocumentBytes = maxDocumentBytes
        self.fileManager = fileManager
    }

    public static func liveDirectory() -> URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("app.fluke", isDirectory: true)
            .appendingPathComponent("browse-cache", isDirectory: true)
    }

    public func load<Value: Codable & Sendable>(
        _ type: Value.Type,
        for key: BrowseCacheKey
    ) throws -> BrowseCacheDocument<Value>? {
        let url = fileURL(for: key)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        if let size = attributes[.size] as? NSNumber,
           size.intValue > maxDocumentBytes {
            throw BrowseCacheError.documentTooLarge
        }
        do {
            let document = try JSONDecoder.fluke.decode(
                BrowseCacheDocument<Value>.self,
                from: Data(contentsOf: url)
            )
            return try validatedDocument(document, key: key)
        } catch let error as BrowseCacheError {
            throw error
        } catch {
            throw BrowseCacheError.corruptDocument
        }
    }

    public func replace<Value: Codable & Sendable>(
        _ document: BrowseCacheDocument<Value>,
        for key: BrowseCacheKey
    ) async throws {
        _ = try validatedDocument(document, key: key)
        let data = try JSONEncoder.fluke.encode(document)
        guard data.count <= maxDocumentBytes else {
            throw BrowseCacheError.documentTooLarge
        }
        try prepareDirectory()
        try await writer.write(data, to: fileURL(for: key))
    }

    public func remove(_ key: BrowseCacheKey) throws {
        let url = fileURL(for: key)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
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
