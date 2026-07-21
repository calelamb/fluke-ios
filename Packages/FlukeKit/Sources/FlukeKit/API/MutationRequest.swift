import Foundation

public enum MutationBodyLimits {
    public static let maximumBytes = 10_000_000
}

struct MutationRequest: Sendable {
    static let maximumBodyBytes = MutationBodyLimits.maximumBytes

    let body: Data
    let contentType: String
    let headers: [String: String]

    init(
        body: Data,
        contentType: String,
        headers: [String: String] = [:]
    ) throws {
        guard body.count <= Self.maximumBodyBytes,
              Self.isSafeHeaderValue(contentType),
              headers.allSatisfy({ key, value in
                  Self.isSafeHeaderName(key)
                      && Self.isSafeHeaderValue(value)
                      && !Self.reservedHeaders.contains(key.lowercased())
              }) else {
            throw APIError.invalidRequest
        }

        self.body = body
        self.contentType = contentType
        self.headers = headers
    }

    private static let reservedHeaders = ["accept", "content-type"]

    private static func isSafeHeaderName(_ value: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "!#$%&'*+-.^_`|~")
        )
        return isBounded(value, maximum: 100, allowed: allowed)
    }

    private static func isSafeHeaderValue(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value == normalized
            && !normalized.isEmpty
            && normalized.count <= 2_000
            && value.unicodeScalars.allSatisfy {
                !CharacterSet.controlCharacters.contains($0)
            }
    }

    private static func isBounded(
        _ value: String,
        maximum: Int,
        allowed: CharacterSet
    ) -> Bool {
        !value.isEmpty
            && value.count <= maximum
            && value.unicodeScalars.allSatisfy(allowed.contains)
    }
}
