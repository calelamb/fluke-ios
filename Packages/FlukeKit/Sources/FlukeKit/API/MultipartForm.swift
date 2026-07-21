import Foundation

public struct MultipartPart: Sendable {
    public let name: String
    public let fileName: String
    public let mimeType: String
    public let bytes: Data

    private init(
        name: String,
        fileName: String,
        mimeType: String,
        bytes: Data
    ) {
        self.name = name
        self.fileName = fileName
        self.mimeType = mimeType
        self.bytes = bytes
    }

    public static func data(
        name: String,
        fileName: String,
        mimeType: String,
        bytes: Data
    ) throws -> MultipartPart {
        guard isSafeDispositionValue(name),
              isSafeDispositionValue(fileName),
              isSafeMIMEType(mimeType) else {
            throw APIError.invalidRequest
        }
        return MultipartPart(
            name: name,
            fileName: fileName,
            mimeType: mimeType,
            bytes: bytes
        )
    }

    private static func isSafeDispositionValue(_ value: String) -> Bool {
        !value.isEmpty
            && value.count <= 255
            && value.unicodeScalars.allSatisfy {
                (0x20...0x7E).contains($0.value)
                    && $0 != "\""
                    && $0 != "\\"
            }
    }

    private static func isSafeMIMEType(_ value: String) -> Bool {
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "!#$&^_.+-")
        )
        return value.count <= 255
            && components.count == 2
            && components.allSatisfy { component in
                !component.isEmpty
                    && component.unicodeScalars.allSatisfy(allowed.contains)
            }
    }
}

public struct MultipartForm: Sendable {
    public let boundary: String
    public let body: Data
    public let contentType: String

    public init(parts: [MultipartPart]) throws {
        guard !parts.isEmpty,
              parts.allSatisfy({ $0.bytes.count <= MutationRequest.maximumBodyBytes }) else {
            throw APIError.invalidRequest
        }

        let boundary = "Fluke-\(UUID().uuidString)"
        guard let byteCount = Self.encodedByteCount(parts: parts, boundary: boundary),
              byteCount <= MutationRequest.maximumBodyBytes else {
            throw APIError.invalidRequest
        }
        let body = Self.encode(parts: parts, boundary: boundary)
        assert(body.count == byteCount)

        self.boundary = boundary
        self.body = body
        self.contentType = "multipart/form-data; boundary=\(boundary)"
    }

    private static func encode(parts: [MultipartPart], boundary: String) -> Data {
        parts.reduce(into: Data()) { body, part in
            body.appendUTF8("--\(boundary)\r\n")
            body.appendUTF8(
                "Content-Disposition: form-data; name=\"\(part.name)\"; "
                    + "filename=\"\(part.fileName)\"\r\n"
            )
            body.appendUTF8("Content-Type: \(part.mimeType)\r\n\r\n")
            body.append(part.bytes)
            body.appendUTF8("\r\n")
        }
        .appendingUTF8("--\(boundary)--\r\n")
    }

    private static func encodedByteCount(
        parts: [MultipartPart],
        boundary: String
    ) -> Int? {
        let closing = "--\(boundary)--\r\n".utf8.count
        return parts.reduce(Optional(closing)) { total, part in
            guard let total else { return nil }
            let header = "--\(boundary)\r\n"
                + "Content-Disposition: form-data; name=\"\(part.name)\"; "
                + "filename=\"\(part.fileName)\"\r\n"
                + "Content-Type: \(part.mimeType)\r\n\r\n"
            let partSize = header.utf8.count + part.bytes.count + 2
            let (sum, overflow) = total.addingReportingOverflow(partSize)
            return overflow ? nil : sum
        }
    }
}

private extension Data {
    mutating func appendUTF8(_ value: String) {
        append(contentsOf: value.utf8)
    }

    func appendingUTF8(_ value: String) -> Data {
        var copy = self
        copy.appendUTF8(value)
        return copy
    }
}
