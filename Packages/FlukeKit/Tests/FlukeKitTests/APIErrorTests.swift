import XCTest
@testable import FlukeKit

final class APIErrorTests: XCTestCase {

    func test_unauthorized_hasReadableDescription() {
        let err = APIError.unauthorized
        XCTAssertEqual(err.errorDescription, "You're not signed in.")
    }

    func test_server_includesStatusAndBody() {
        let err = APIError.server(status: 500, body: "boom")
        XCTAssertTrue(err.errorDescription?.contains("500") ?? false)
        XCTAssertTrue(err.errorDescription?.contains("boom") ?? false)
    }

    func test_network_includesUnderlyingMessage() {
        let underlying = NSError(domain: "Net", code: -1009, userInfo: [
            NSLocalizedDescriptionKey: "Offline"
        ])
        let err = APIError.network(underlying)
        XCTAssertTrue(err.errorDescription?.contains("Offline") ?? false)
    }

    func test_decoding_includesType() {
        let err = APIError.decoding("Whale")
        XCTAssertTrue(err.errorDescription?.contains("Whale") ?? false)
    }
}
