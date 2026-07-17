import XCTest
@testable import FlukeKit

final class APIErrorTests: XCTestCase {

    func test_unauthorized_hasReadableDescription() {
        let err = APIError.unauthorized
        XCTAssertEqual(err.errorDescription, "You're not signed in.")
    }

    func test_remote_usesOnlySafeMessage() {
        let err = APIError.remote(
            status: 500,
            code: "UPSTREAM_FAILURE",
            message: "Try again later.",
            retryable: true,
            requestId: "req-1"
        )
        XCTAssertEqual(err.errorDescription, "Try again later.")
        XCTAssertTrue(err.retryable)
    }

    func test_offline_hasSafeDescription() {
        let err = APIError.offline
        XCTAssertEqual(err.errorDescription, "You're offline.")
        XCTAssertTrue(err.retryable)
    }

    func test_decoding_includesType() {
        let err = APIError.decoding("Whale")
        XCTAssertEqual(err.errorDescription, "Fluke couldn't read the service response.")
    }

    func test_invalidPagination_hasSafeDescription() {
        let err = APIError.invalidPagination
        XCTAssertEqual(err.errorDescription, "Fluke received an invalid service response.")
    }
}
