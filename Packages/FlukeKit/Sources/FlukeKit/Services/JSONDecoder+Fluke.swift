import Foundation

public extension JSONDecoder {
    /// Project-default decoder. Handles Prisma's ISO-8601 date strings
    /// (with milliseconds) and string-encoded `Decimal` coords.
    static var fluke: JSONDecoder {
        let decoder = JSONDecoder()
        let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let plain = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = try? fractional.parse(string) { return date }
            if let date = try? plain.parse(string) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Bad ISO8601: \(string)"
            )
        }
        return decoder
    }
}

public extension JSONEncoder {
    static var fluke: JSONEncoder {
        let encoder = JSONEncoder()
        let format = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(format))
        }
        return encoder
    }
}
