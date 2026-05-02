import Foundation

public extension JSONDecoder {
    /// Project-default decoder. Handles Prisma's ISO-8601 date strings
    /// (with milliseconds) and string-encoded `Decimal` coords.
    static let fluke: JSONDecoder = {
        let d = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        d.dateDecodingStrategy = .custom { decoder in
            let str = try decoder.singleValueContainer().decode(String.self)
            if let date = formatter.date(from: str) { return date }
            // Fallback for dates without fractional seconds.
            let plain = ISO8601DateFormatter()
            if let date = plain.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Bad ISO8601: \(str)"
            )
        }
        return d
    }()
}
