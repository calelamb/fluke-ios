import Foundation
import OSLog

public enum BrowseCacheOperation: String, Sendable {
    case read
    case write
    case prune
}

public struct BrowseCacheDiagnostic: Equatable, Sendable {
    public let operation: BrowseCacheOperation
    public let resource: String
    public let errorCode: String

    public init(operation: BrowseCacheOperation, resource: String, errorCode: String) {
        self.operation = operation
        self.resource = resource
        self.errorCode = errorCode
    }
}

public protocol BrowseCacheDiagnostics: Sendable {
    func record(_ diagnostic: BrowseCacheDiagnostic) async
}

public struct NoopBrowseCacheDiagnostics: BrowseCacheDiagnostics {
    public init() {}

    public func record(_ diagnostic: BrowseCacheDiagnostic) async {}
}

public struct SystemBrowseCacheDiagnostics: BrowseCacheDiagnostics {
    private let logger = Logger(subsystem: "app.fluke", category: "BrowseCache")

    public init() {}

    public func record(_ diagnostic: BrowseCacheDiagnostic) async {
        logger.error(
            "Cache \(diagnostic.operation.rawValue, privacy: .public) failed for \(diagnostic.resource, privacy: .public): \(diagnostic.errorCode, privacy: .public)"
        )
    }
}

func cacheErrorCode(_ error: Error) -> String {
    if let cacheError = error as? BrowseCacheError {
        return String(describing: cacheError)
    }
    return "ioFailure"
}
