import CryptoKit
import Foundation

public struct BrowseCacheKey: Hashable, Sendable {
    public let resource: String
    public let filename: String

    public init(resource: String, identity: String) {
        let safeResource = resource
            .lowercased()
            .map { character in
                character.isLetter || character.isNumber || character == "-" ? character : "-"
            }
        let normalizedResource = String(safeResource).trimmingCharacters(
            in: CharacterSet(charactersIn: "-")
        )
        self.resource = normalizedResource.isEmpty ? "browse" : normalizedResource
        let digest = SHA256.hash(data: Data("\(resource)\u{0}\(identity)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        self.filename = "\(self.resource)-\(digest).json"
    }
}
