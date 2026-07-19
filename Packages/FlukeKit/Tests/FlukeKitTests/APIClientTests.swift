import XCTest

@testable import FlukeKit

final class APIClientTests: XCTestCase {

  private var client: APIClient!
  private var mockSession: MockURLProtocolSession!

  override func setUp() async throws {
    mockSession = MockURLProtocolSession()
    let session = URLSession(configuration: mockSession.configuration)
    client = APIClient(
      baseURL: URL(string: "http://localhost:4000")!,
      session: session
    )
  }

  override func tearDown() async throws {
    mockSession.reset()
    mockSession = nil
    client = nil
  }

  func test_get_decodesPaginatedWhaleResponse() async throws {
    let body = try FixtureLoader.data(named: "whales")

    mockSession.install { request in
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
    mockSession.install { request in
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
    mockSession.install { request in
      (
        HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!,
        "boom".data(using: .utf8)!
      )
    }

    do {
      let _: [Whale] = try await client.get("/api/v1/whales")
      XCTFail("expected throw")
    } catch let error as APIError {
      XCTAssertEqual(
        error,
        .remote(
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
      .value: "abc123",
    ])!
    client.cookieStorage.setCookie(cookie)

    mockSession.install { request in
      let cookieHeader = request.value(forHTTPHeaderField: "Cookie") ?? ""
      XCTAssertTrue(cookieHeader.contains("fluke_admin=abc123"))
      return (
        HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
        "[]".data(using: .utf8)!
      )
    }

    let _: [Whale] = try await client.get("/api/v1/whales")
  }

  func test_clearCookies_removesExactAndParentDomainCookiesOnly() throws {
    let configuration = URLSessionConfiguration.ephemeral
    let session = URLSession(configuration: configuration)
    let apiClient = try XCTUnwrap(
      APIClient(
        baseURL: XCTUnwrap(URL(string: "https://api.fluke.app")),
        session: session
      ))
    let exact = try cookie(domain: "api.fluke.app", name: "exact")
    let parent = try cookie(domain: ".fluke.app", name: "parent")
    let unrelated = try cookie(domain: ".notfluke.app", name: "unrelated")
    [exact, parent, unrelated].forEach(apiClient.cookieStorage.setCookie)

    apiClient.clearCookies()

    let remainingNames = Set(apiClient.cookieStorage.cookies?.map(\.name) ?? [])
    XCTAssertFalse(remainingNames.contains("exact"))
    XCTAssertFalse(remainingNames.contains("parent"))
    XCTAssertTrue(remainingNames.contains("unrelated"))
  }

  func test_clearCookies_doesNotDeleteSuffixLookalikeDomain() throws {
    let configuration = URLSessionConfiguration.ephemeral
    let apiClient = try XCTUnwrap(
      APIClient(
        baseURL: XCTUnwrap(URL(string: "https://api.fluke.app")),
        session: URLSession(configuration: configuration)
      ))
    let lookalike = try cookie(domain: ".evilfluke.app", name: "lookalike")
    apiClient.cookieStorage.setCookie(lookalike)

    apiClient.clearCookies()

    XCTAssertTrue(
      apiClient.cookieStorage.cookies?.contains(where: { $0.name == "lookalike" }) == true)
  }

  private func cookie(domain: String, name: String) throws -> HTTPCookie {
    try XCTUnwrap(
      HTTPCookie(properties: [
        .domain: domain,
        .path: "/",
        .name: name,
        .value: "value",
        .secure: "TRUE",
      ]))
  }
}
