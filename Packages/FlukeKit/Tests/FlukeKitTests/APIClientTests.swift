import XCTest
@testable import FlukeKit

final class APIClientTests: XCTestCase {

    private var client: APIClient!

    override func setUp() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        client = APIClient(
            baseURL: URL(string: "http://localhost:4000")!,
            session: session
        )
    }

    override func tearDown() async throws {
        MockURLProtocol.handler = nil
        client = nil
    }

    func test_get_decodesPaginatedWhaleResponse() async throws {
        let body = try FixtureLoader.data(named: "whales")

        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/whales")
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                body
            )
        }

        let response: PaginatedResponse<Whale> = try await client.get("/api/v1/whales")
        XCTAssertEqual(response.items.count, 1)
        XCTAssertEqual(response.items.first?.catalogId, "FX-001")
        XCTAssertFalse(response.page.hasMore)
    }

    func test_get_throwsUnauthorizedOn401() async {
        MockURLProtocol.handler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                Data()
            )
        }

        do {
            let _: [Whale] = try await client.get("/api/v1/whales")
            XCTFail("expected throw")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func test_get_throwsServerOn500() async {
        MockURLProtocol.handler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!,
                "boom".data(using: .utf8)!
            )
        }

        do {
            let _: [Whale] = try await client.get("/api/v1/whales")
            XCTFail("expected throw")
        } catch let error as APIError {
            XCTAssertEqual(error, .remote(
                status: 500,
                code: "REMOTE_ERROR",
                message: "The service could not complete the request.",
                retryable: true,
                requestId: nil
            ))
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func test_get_includesCookiesAutomatically() async throws {
        let cookie = HTTPCookie(properties: [
            .domain: "localhost",
            .path: "/",
            .name: "fluke_admin",
            .value: "abc123"
        ])!
        client.cookieStorage.setCookie(cookie)

        MockURLProtocol.handler = { request in
            let cookieHeader = request.value(forHTTPHeaderField: "Cookie") ?? ""
            XCTAssertTrue(cookieHeader.contains("fluke_admin=abc123"))
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                "[]".data(using: .utf8)!
            )
        }

        let _: [Whale] = try await client.get("/api/v1/whales")
    }
}
