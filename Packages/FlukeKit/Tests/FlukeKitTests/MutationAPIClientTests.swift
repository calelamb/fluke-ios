import Foundation
import Testing

@testable import FlukeKit

private let validMutationCSRFToken =
  "\(String(repeating: "a", count: 43)).\(String(repeating: "b", count: 43))"
private let otherMutationCSRFToken =
  "\(String(repeating: "c", count: 43)).\(String(repeating: "d", count: 43))"

@Suite("Mutation API client")
struct MutationAPIClientTests {
  @Test(
    "CSRF cookie must be exact secure and API-origin matching",
    arguments: [
      ("fluke_csrf", "api.fluke.test", "/api/v1", false),
      ("Fluke_Csrf", "api.fluke.test", "/api/v1", true),
      ("fluke_csrf", "other.fluke.test", "/api/v1", true),
      ("fluke_csrf", "api.fluke.test", "/", true),
      ("fluke_csrf", "api.fluke.test", "/api", true),
      ("fluke_csrf", "api.fluke.test", "/api/v1/auth", true),
    ])
  func rejectsUnsafeCSRFCookie(name: String, domain: String, path: String, secure: Bool)
    async throws
  {
    let storage = HTTPCookieStorage.sharedCookieStorage(
      forGroupContainerIdentifier: UUID().uuidString)
    var properties: [HTTPCookiePropertyKey: Any] = [
      .domain: domain, .path: path, .name: name,
      .value: validMutationCSRFToken,
    ]
    if secure { properties[.secure] = "TRUE" }
    let cookie = try #require(HTTPCookie(properties: properties))
    storage.setCookie(cookie)
    let transport = MutationTransport([])
    let client = APIClient(
      baseURL: URL(string: "https://api.fluke.test")!, transport: transport,
      cookieStorage: storage
    )

    await #expect(throws: APIError.invalidRequest) {
      try await client.postOKWithCSRF(APIRequest(path: "/api/v1/auth/logout"))
    }
    #expect(await transport.requests.isEmpty)
  }

  @Test("CSRF cookie rejects duplicates and unsafe values")
  func rejectsDuplicateCSRFCookies() async throws {
    let storage = HTTPCookieStorage.sharedCookieStorage(
      forGroupContainerIdentifier: UUID().uuidString)
    for path in ["/", "/api/v1"] {
      storage.setCookie(
        try #require(
          HTTPCookie(properties: [
            .domain: "api.fluke.test", .path: path, .name: "fluke_csrf",
            .value: path == "/" ? otherMutationCSRFToken : validMutationCSRFToken,
            .secure: "TRUE",
          ])))
    }
    let client = APIClient(
      baseURL: URL(string: "https://api.fluke.test")!, transport: MutationTransport([]),
      cookieStorage: storage
    )
    await #expect(throws: APIError.invalidRequest) {
      try await client.postOKWithCSRF(APIRequest(path: "/api/v1/auth/logout"))
    }
  }

  @Test(
    "CSRF cookie rejects missing and malformed values",
    arguments: [
      nil, String(repeating: "c", count: 86),
      "\(String(repeating: "c", count: 42)).\(String(repeating: "d", count: 43))",
      "\(String(repeating: "c", count: 43))..\(String(repeating: "d", count: 43))",
      "\(String(repeating: "c", count: 43)).\(String(repeating: "d", count: 42))!",
    ])
  func rejectsMalformedCSRFValue(value: String?) async throws {
    let storage = HTTPCookieStorage.sharedCookieStorage(
      forGroupContainerIdentifier: UUID().uuidString)
    if let value {
      storage.setCookie(
        try #require(
          HTTPCookie(properties: [
            .domain: "api.fluke.test", .path: "/api/v1", .name: "fluke_csrf",
            .value: value, .secure: "TRUE",
          ])))
    }
    let transport = MutationTransport([])
    let client = APIClient(
      baseURL: URL(string: "https://api.fluke.test")!, transport: transport,
      cookieStorage: storage
    )

    await #expect(throws: APIError.invalidRequest) {
      try await client.postOKWithCSRF(APIRequest(path: "/api/v1/auth/logout"))
    }
    #expect(await transport.requests.isEmpty)
  }

  @Test("JSON POST uses the canonical content type and encoded body")
  func jsonPost() async throws {
    let transport = MutationTransport([
      .response(status: 201, body: Data(#"{"id":"created"}"#.utf8))
    ])
    let client = makeClient(transport: transport)

    let response: MutationResponse = try await client.post(
      APIRequest(path: "/api/v1/sightings"),
      body: MutationBody(note: "Transient orca")
    )
    let request = try #require(await transport.requests.first)

    #expect(response.id == "created")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    #expect(request.httpBody == Data(#"{"note":"Transient orca"}"#.utf8))
  }

  @Test("Multipart POST uses its generated boundary and custom safe headers")
  func multipartPost() async throws {
    let transport = MutationTransport([
      .response(status: 200, body: Data(#"{"id":"photo"}"#.utf8))
    ])
    let client = makeClient(transport: transport)
    let part = try MultipartPart.data(
      name: "photo",
      fileName: "fin.jpg",
      mimeType: "image/jpeg",
      bytes: Data([0x01, 0x02])
    )

    let _: MutationResponse = try await client.postMultipart(
      APIRequest(path: "/api/v1/sightings/one/photos"),
      parts: [part],
      headers: ["X-Upload-Token": "safe-token"]
    )
    let request = try #require(await transport.requests.first)
    let contentType = try #require(request.value(forHTTPHeaderField: "Content-Type"))

    #expect(contentType.hasPrefix("multipart/form-data; boundary="))
    #expect(request.value(forHTTPHeaderField: "X-Upload-Token") == "safe-token")
    #expect(!(request.httpBody ?? Data()).isEmpty)
  }

  @Test("Mutation retries one transient transport failure before any response")
  func transientRetry() async throws {
    let transport = MutationTransport([
      .failure(URLError(.networkConnectionLost)),
      .response(status: 200, body: Data(#"{"id":"retried"}"#.utf8)),
    ])
    let client = makeClient(transport: transport)

    let response: MutationResponse = try await client.post(
      APIRequest(path: "/api/v1/sightings"),
      body: MutationBody(note: "Retry once")
    )

    #expect(response.id == "retried")
    #expect(await transport.requests.count == 2)
  }

  @Test("JSON POST can disable retry for one-use credentials")
  func jsonPostWithoutRetry() async throws {
    let transport = MutationTransport([
      .failure(URLError(.networkConnectionLost)),
      .response(status: 200, body: Data(#"{"id":"must-not-run"}"#.utf8)),
    ])
    let client = makeClient(transport: transport)

    await #expect(throws: APIError.transport) {
      let _: MutationResponse = try await client.post(
        APIRequest(path: "/api/v1/auth/apple"),
        body: MutationBody(note: "one use"),
        retryPolicy: .never
      )
    }
    #expect(await transport.requests.count == 1)
  }

  @Test("Multipart keeps one transient retry by default")
  func multipartDefaultRetry() async throws {
    let transport = MutationTransport([
      .failure(URLError(.networkConnectionLost)),
      .response(status: 200, body: Data(#"{"id":"retried-photo"}"#.utf8)),
    ])
    let client = makeClient(transport: transport)
    let part = try MultipartPart.data(
      name: "photo",
      fileName: "fin.jpg",
      mimeType: "image/jpeg",
      bytes: Data([0x01])
    )

    let response: MutationResponse = try await client.postMultipart(
      APIRequest(path: "/api/v1/sightings/one/photos"),
      parts: [part]
    )

    #expect(response.id == "retried-photo")
    #expect(await transport.requests.count == 2)
  }

  @Test("HTTP 4xx is returned safely and never retried")
  func clientFailureDoesNotRetry() async {
    let transport = MutationTransport([
      .response(status: 422, body: Data("internal database detail".utf8))
    ])
    let client = makeClient(transport: transport)

    await #expect(
      throws: APIError.remote(
        status: 422,
        code: "REMOTE_ERROR",
        message: "The service could not complete the request.",
        retryable: false,
        requestId: nil
      )
    ) {
      let _: MutationResponse = try await client.post(
        APIRequest(path: "/api/v1/sightings"),
        body: MutationBody(note: "Do not retry")
      )
    }
    #expect(await transport.requests.count == 1)
  }

  @Test("Caller cancellation remains CancellationError")
  func cancellation() async throws {
    let transport = MutationTransport([.delayed])
    let client = makeClient(transport: transport)
    let task = Task<MutationResponse, Error> {
      try await client.post(
        APIRequest(path: "/api/v1/sightings"),
        body: MutationBody(note: "Cancel")
      )
    }
    await Task.yield()
    task.cancel()

    await #expect(throws: CancellationError.self) {
      try await task.value
    }
    #expect(await transport.requests.count == 1)
  }

  @Test("Oversized JSON and injected custom headers fail before transport")
  func requestValidation() async throws {
    let transport = MutationTransport([])
    let client = makeClient(transport: transport)

    await #expect(throws: APIError.invalidRequest) {
      let _: MutationResponse = try await client.post(
        APIRequest(path: "/api/v1/sightings"),
        body: MutationBody(note: String(repeating: "a", count: 10_000_001))
      )
    }

    let part = try MultipartPart.data(
      name: "photo",
      fileName: "fin.jpg",
      mimeType: "image/jpeg",
      bytes: Data([0x01])
    )
    await #expect(throws: APIError.invalidRequest) {
      let _: MutationResponse = try await client.postMultipart(
        APIRequest(path: "/api/v1/sightings/one/photos"),
        parts: [part],
        headers: ["X-Upload-Token": "safe\r\nX-Evil: yes"]
      )
    }

    #expect(throws: APIError.invalidRequest) {
      try MutationRequest(
        body: Data([0x01]),
        contentType: "application/json",
        headers: ["X-Upload-Token": "safe\n"]
      )
    }

    #expect(await transport.requests.isEmpty)
  }

  private func makeClient(transport: MutationTransport) -> APIClient {
    APIClient(
      baseURL: URL(string: "https://api.fluke.test")!,
      transport: transport,
      requestTimeout: .seconds(2)
    )
  }
}

@Suite("Mutation cookies", .serialized)
struct MutationCookieTests {
  @Test("Mutation requests apply URLSession cookies")
  func mutationCookies() async throws {
    let mockSession = MockURLProtocolSession()
    let client = APIClient(
      baseURL: URL(string: "https://api.fluke.test")!,
      session: URLSession(configuration: mockSession.configuration)
    )
    let cookie = try #require(
      HTTPCookie(properties: [
        .domain: "api.fluke.test",
        .path: "/",
        .name: "fluke_session",
        .value: "cookie-value",
        .secure: "TRUE",
      ]))
    client.cookieStorage.setCookie(cookie)
    defer { mockSession.reset() }

    mockSession.install { request in
      #expect(
        request.value(forHTTPHeaderField: "Cookie")?
          .contains("fluke_session=cookie-value") == true
      )
      return (
        HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!,
        Data(#"{"id":"cookie"}"#.utf8)
      )
    }

    let response: MutationResponse = try await client.post(
      APIRequest(path: "/api/v1/sightings"),
      body: MutationBody(note: "Cookie")
    )

    #expect(response.id == "cookie")
  }
}

private struct MutationBody: Codable, Sendable {
  let note: String
}

private struct MutationResponse: Codable, Sendable {
  let id: String
}

private actor MutationTransport: HTTPTransport {
  enum Step: @unchecked Sendable {
    case delayed
    case failure(Error)
    case response(status: Int, body: Data)
  }

  private var steps: [Step]
  private(set) var requests: [URLRequest] = []

  init(_ steps: [Step]) {
    self.steps = steps
  }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    requests.append(request)
    guard !steps.isEmpty else { throw URLError(.badServerResponse) }
    let step = steps.removeFirst()

    switch step {
    case .delayed:
      try await Task.sleep(for: .seconds(30))
      throw URLError(.timedOut)
    case .failure(let error):
      throw error
    case .response(let status, let body):
      return (
        body,
        HTTPURLResponse(
          url: request.url!,
          statusCode: status,
          httpVersion: nil,
          headerFields: nil
        )!
      )
    }
  }
}
