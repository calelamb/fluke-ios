import Foundation
import Testing

@testable import FlukeKit

@Suite("Validated multipart form")
struct MultipartFormTests {
    @Test("Multipart builder rejects header injection and oversized photos")
    func multipartValidation() throws {
        #expect(throws: APIError.invalidRequest) {
            try MultipartPart.data(
                name: "photo\r\nX-Evil: yes",
                fileName: "fin.jpg",
                mimeType: "image/jpeg",
                bytes: Data()
            )
        }
        #expect(throws: APIError.invalidRequest) {
            try MultipartForm(parts: [
                .data(
                    name: "photo",
                    fileName: "fin.jpg",
                    mimeType: "image/jpeg",
                    bytes: Data(repeating: 0, count: 10_000_001)
                )
            ])
        }
    }

    @Test("Multipart form emits one generated boundary and canonical headers")
    func canonicalEncoding() throws {
        let form = try MultipartForm(parts: [
            .data(
                name: "photo",
                fileName: "fin.jpg",
                mimeType: "image/jpeg",
                bytes: Data([0x01, 0x02, 0x03])
            )
        ])
        let text = String(decoding: form.body, as: UTF8.self)

        #expect(!form.boundary.isEmpty)
        #expect(form.contentType == "multipart/form-data; boundary=\(form.boundary)")
        #expect(text.hasPrefix("--\(form.boundary)\r\n"))
        #expect(text.contains("Content-Disposition: form-data; name=\"photo\"; filename=\"fin.jpg\""))
        #expect(text.contains("Content-Type: image/jpeg\r\n\r\n"))
        #expect(text.hasSuffix("\r\n--\(form.boundary)--\r\n"))
    }

    @Test("Multipart metadata rejects quote and MIME injection")
    func metadataValidation() {
        #expect(throws: APIError.invalidRequest) {
            try MultipartPart.data(
                name: "photo",
                fileName: "fin\".jpg",
                mimeType: "image/jpeg",
                bytes: Data()
            )
        }
        #expect(throws: APIError.invalidRequest) {
            try MultipartPart.data(
                name: "photo",
                fileName: "fin.jpg",
                mimeType: "image/jpeg\r\nX-Evil: yes",
                bytes: Data()
            )
        }
        #expect(throws: APIError.invalidRequest) {
            try MultipartPart.data(
                name: "photo",
                fileName: #"fin\name.jpg"#,
                mimeType: "image/jpeg",
                bytes: Data()
            )
        }
        #expect(throws: APIError.invalidRequest) {
            try MultipartPart.data(
                name: "photo",
                fileName: "fin.jpg",
                mimeType: "image/" + String(repeating: "x", count: 256),
                bytes: Data()
            )
        }
    }
}
