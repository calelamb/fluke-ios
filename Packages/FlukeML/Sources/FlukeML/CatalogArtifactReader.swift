import Darwin
import Foundation

enum CatalogArtifactReader {
    private static let directoryFlags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
    private static let fileFlags = O_RDONLY | O_NOFOLLOW | O_CLOEXEC
    private static let readChunkBytes = 64 * 1_024

    static func withDirectory<Result>(
        at directory: URL,
        _ body: (Int32) throws -> Result
    ) throws -> Result {
        guard directory.isFileURL, directory.path == directory.standardizedFileURL.path else {
            throw IdentifierArtifactError.invalidArtifactDirectory
        }
        return try withSubdirectory(
            parent: directory.deletingLastPathComponent(),
            name: directory.lastPathComponent,
            body
        )
    }

    static func withSubdirectory<Result>(
        parent: URL,
        name: String,
        _ body: (Int32) throws -> Result
    ) throws -> Result {
        guard parent.isFileURL, isSafeComponent(name) else {
            throw IdentifierArtifactError.invalidArtifactDirectory
        }
        let parentDescriptor = Darwin.open(parent.path, directoryFlags)
        guard parentDescriptor >= 0 else {
            throw IdentifierArtifactError.invalidArtifactDirectory
        }
        defer { Darwin.close(parentDescriptor) }

        let directoryDescriptor = Darwin.openat(parentDescriptor, name, directoryFlags)
        guard directoryDescriptor >= 0 else {
            throw IdentifierArtifactError.invalidArtifactDirectory
        }
        defer { Darwin.close(directoryDescriptor) }
        try requireExactEntries(directoryDescriptor)
        return try body(directoryDescriptor)
    }

    static func readJSON(
        named name: String,
        from directoryDescriptor: Int32,
        maximumBytes: Int
    ) throws -> Data {
        try readFile(
            named: name,
            from: directoryDescriptor,
            size: .maximum(maximumBytes)
        )
    }

    static func readExact(
        named name: String,
        from directoryDescriptor: Int32,
        byteCount: Int
    ) throws -> Data {
        try readFile(
            named: name,
            from: directoryDescriptor,
            size: .exact(byteCount)
        )
    }
}

private extension CatalogArtifactReader {
    enum SizeConstraint {
        case maximum(Int)
        case exact(Int)

        var limit: Int {
            switch self {
            case .maximum(let value), .exact(let value):
                return value
            }
        }
    }

    static let requiredFiles = Set(["manifest.json", "metadata.json", "references.f16"])

    static func isSafeComponent(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.contains("/")
            && !value.contains("\0")
    }

    static func requireExactEntries(_ directoryDescriptor: Int32) throws {
        let duplicate = Darwin.dup(directoryDescriptor)
        guard duplicate >= 0 else { throw IdentifierArtifactError.invalidArtifactDirectory }
        guard let stream = Darwin.fdopendir(duplicate) else {
            Darwin.close(duplicate)
            throw IdentifierArtifactError.invalidArtifactDirectory
        }
        defer { Darwin.closedir(stream) }
        var names = Set<String>()
        errno = 0
        while let entry = Darwin.readdir(stream) {
            let name = withUnsafePointer(to: entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) {
                    String(cString: $0)
                }
            }
            if name != ".", name != ".." {
                names.insert(name)
            }
        }
        guard errno == 0, names == requiredFiles else {
            throw IdentifierArtifactError.invalidArtifactDirectory
        }
    }

    static func readFile(
        named name: String,
        from directoryDescriptor: Int32,
        size: SizeConstraint
    ) throws -> Data {
        guard isSafeComponent(name) else {
            throw IdentifierArtifactError.unreadableArtifact(name)
        }
        let descriptor = Darwin.openat(directoryDescriptor, name, fileFlags)
        guard descriptor >= 0 else {
            if errno == ENOENT {
                throw IdentifierArtifactError.missingArtifact(name)
            }
            throw IdentifierArtifactError.unreadableArtifact(name)
        }
        defer { Darwin.close(descriptor) }
        try validateOpenedFile(descriptor, name: name, size: size)
        return try readBounded(descriptor, name: name, size: size)
    }

    static func validateOpenedFile(
        _ descriptor: Int32,
        name: String,
        size: SizeConstraint
    ) throws {
        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_size >= 0 else {
            throw IdentifierArtifactError.unreadableArtifact(name)
        }
        let fileSize = UInt64(metadata.st_size)
        guard fileSize <= UInt64(Int.max) else {
            throw sizeError(name: name, size: size)
        }
        switch size {
        case .maximum(let limit):
            guard fileSize <= UInt64(limit) else {
                throw IdentifierArtifactError.artifactTooLarge(name)
            }
        case .exact(let expected):
            guard fileSize == UInt64(expected) else {
                throw IdentifierArtifactError.invalidVectorLength
            }
        }
    }

    static func readBounded(
        _ descriptor: Int32,
        name: String,
        size: SizeConstraint
    ) throws -> Data {
        var result = Data()
        result.reserveCapacity(size.limit)
        var buffer = [UInt8](repeating: 0, count: min(readChunkBytes, size.limit + 1))
        while result.count <= size.limit {
            let remaining = size.limit + 1 - result.count
            let requested = min(buffer.count, remaining)
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, requested)
            }
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw IdentifierArtifactError.unreadableArtifact(name)
            }
            result.append(contentsOf: buffer.prefix(count))
        }
        guard result.count <= size.limit else {
            throw sizeError(name: name, size: size)
        }
        if case .exact(let expected) = size, result.count != expected {
            throw IdentifierArtifactError.invalidVectorLength
        }
        return result
    }

    static func sizeError(name: String, size: SizeConstraint) -> IdentifierArtifactError {
        switch size {
        case .maximum:
            return .artifactTooLarge(name)
        case .exact:
            return .invalidVectorLength
        }
    }
}
