import Foundation

public enum MultipartRetryPolicy: Sendable {
  case transientOnce
  case never
}

public enum JSONRetryPolicy: Sendable {
  case transientOnce
  case never
}

public struct APIClient: Sendable {
  public static let defaultRequestTimeout: Duration = .seconds(15)

  public let baseURL: URL
  private let transport: any HTTPTransport
  private let requestTimeout: Duration
  private let cookies: HTTPCookieStorage?

  public var cookieStorage: HTTPCookieStorage {
    cookies ?? .shared
  }

  public init(baseURL: URL, session: URLSession = .shared) {
    self.init(
      baseURL: baseURL,
      transport: URLSessionTransport(session: session),
      requestTimeout: Self.defaultRequestTimeout,
      cookies: session.configuration.httpCookieStorage
    )
  }

  public init(
    baseURL: URL,
    transport: any HTTPTransport,
    requestTimeout: Duration = APIClient.defaultRequestTimeout,
    cookieStorage: HTTPCookieStorage? = nil
  ) {
    self.init(
      baseURL: baseURL,
      transport: transport,
      requestTimeout: requestTimeout,
      cookies: cookieStorage
    )
  }

  private init(
    baseURL: URL,
    transport: any HTTPTransport,
    requestTimeout: Duration,
    cookies: HTTPCookieStorage?
  ) {
    self.baseURL = baseURL
    self.transport = transport
    self.requestTimeout = requestTimeout
    self.cookies = cookies
  }

  public func get<T: Decodable>(_ path: String) async throws -> T {
    guard let components = URLComponents(string: path) else {
      throw APIError.malformedResponse
    }
    return try await get(
      APIRequest(
        path: components.path,
        queryItems: components.queryItems ?? []
      ))
  }

  public func get<T: Decodable>(_ apiRequest: APIRequest) async throws -> T {
    try await send(method: "GET", request: apiRequest, mutation: nil)
  }

  public func post<Request: Encodable & Sendable, Response: Decodable>(
    _ request: APIRequest,
    body: Request,
    headers: [String: String] = [:],
    retryPolicy: JSONRetryPolicy = .transientOnce
  ) async throws -> Response {
    let encodedBody: Data
    do {
      encodedBody = try JSONEncoder().encode(body)
    } catch {
      throw APIError.invalidRequest
    }
    let mutation = try MutationRequest(
      body: encodedBody,
      contentType: "application/json",
      headers: headers
    )
    return try await send(
      method: "POST",
      request: request,
      mutation: mutation,
      retriesTransientFailure: retryPolicy == .transientOnce
    )
  }

  public func postMultipart<Response: Decodable>(
    _ request: APIRequest,
    parts: [MultipartPart],
    headers: [String: String] = [:],
    retryPolicy: MultipartRetryPolicy = .transientOnce
  ) async throws -> Response {
    let form = try MultipartForm(parts: parts)
    let mutation = try MutationRequest(
      body: form.body,
      contentType: form.contentType,
      headers: headers
    )
    return try await send(
      method: "POST",
      request: request,
      mutation: mutation,
      retriesTransientFailure: retryPolicy == .transientOnce
    )
  }

  public func postNoContent<Request: Encodable & Sendable>(
    _ request: APIRequest,
    body: Request
  ) async throws {
    let encodedBody: Data
    do {
      encodedBody = try JSONEncoder().encode(body)
    } catch {
      throw APIError.invalidRequest
    }
    try await sendNoContent(
      method: "POST",
      request: request,
      mutation: try MutationRequest(
        body: encodedBody,
        contentType: "application/json"
      )
    )
  }

  public func deleteNoContent(_ request: APIRequest) async throws {
    try await sendNoContent(method: "DELETE", request: request, mutation: nil)
  }

  public func postOKWithCSRF(_ request: APIRequest) async throws {
    try await sendOKWithCSRF(method: "POST", request: request, body: nil)
  }

  public func deleteOKWithCSRF<Request: Encodable & Sendable>(
    _ request: APIRequest,
    body: Request
  ) async throws {
    let encodedBody: Data
    do {
      encodedBody = try JSONEncoder().encode(body)
    } catch {
      throw APIError.invalidRequest
    }
    try await sendOKWithCSRF(method: "DELETE", request: request, body: encodedBody)
  }

  public func validatedCSRFCookieValue(for request: APIRequest) throws -> String {
    let url = try request.url(relativeTo: baseURL)
    guard url.scheme?.lowercased() == "https",
      let host = url.host?.lowercased(),
      let cookies
    else {
      throw APIError.invalidRequest
    }
    let candidates = (cookies.cookies(for: url) ?? []).filter {
      $0.name.lowercased() == "fluke_csrf"
    }
    guard candidates.count == 1, let cookie = candidates.first,
      cookie.name == "fluke_csrf", cookie.isSecure,
      cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) == host,
      cookie.path == "/api/v1",
      Self.isValidCSRFToken(cookie.value)
    else {
      throw APIError.invalidRequest
    }
    return cookie.value
  }

  private static func isValidCSRFToken(_ value: String) -> Bool {
    let segments = value.split(separator: ".", omittingEmptySubsequences: false)
    guard value.count == 87, segments.count == 2 else { return false }
    return segments.allSatisfy { segment in
      segment.count == 43
        && segment.unicodeScalars.allSatisfy {
          CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
        }
    }
  }

  public func clearCookies() {
    guard let cookies, let host = baseURL.host?.lowercased() else { return }
    let matchingCookies =
      cookies.cookies?
      .filter { cookie in
        let domain = cookie.domain
          .lowercased()
          .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return host == domain || host.hasSuffix(".\(domain)")
      } ?? []
    for cookie in matchingCookies {
      cookies.deleteCookie(cookie)
    }
  }

  private func send<T: Decodable>(
    method: String,
    request apiRequest: APIRequest,
    mutation: MutationRequest?,
    retriesTransientFailure: Bool = false,
    expectedStatus: Int? = nil
  ) async throws -> T {
    let request = try makeURLRequest(
      method: method,
      apiRequest: apiRequest,
      mutation: mutation
    )

    let data: Data
    let response: HTTPURLResponse
    do {
      (data, response) = try await transportData(
        for: request,
        retriesTransientFailure: retriesTransientFailure
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as APIError {
      throw error
    } catch let error as URLError where error.code == .notConnectedToInternet {
      throw APIError.offline
    } catch let error as URLError where error.code == .timedOut {
      throw APIError.timeout
    } catch {
      throw APIError.transport
    }

    switch response.statusCode {
    case 200...299:
      guard expectedStatus == nil || response.statusCode == expectedStatus else {
        throw APIError.malformedResponse
      }
      do {
        return try JSONDecoder.fluke.decode(T.self, from: data)
      } catch {
        throw APIError.decoding(String(describing: T.self))
      }
    case 401:
      throw APIError.unauthorized
    default:
      throw decodeRemoteError(status: response.statusCode, data: data)
    }
  }

  private func sendNoContent(
    method: String,
    request apiRequest: APIRequest,
    mutation: MutationRequest?
  ) async throws {
    let request = try makeURLRequest(
      method: method,
      apiRequest: apiRequest,
      mutation: mutation
    )
    let data: Data
    let response: HTTPURLResponse
    do {
      (data, response) = try await transportData(
        for: request,
        retriesTransientFailure: false
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as APIError {
      throw error
    } catch let error as URLError where error.code == .notConnectedToInternet {
      throw APIError.offline
    } catch let error as URLError where error.code == .timedOut {
      throw APIError.timeout
    } catch {
      throw APIError.transport
    }

    guard response.statusCode == 204, data.isEmpty else {
      if response.statusCode == 401 {
        throw APIError.unauthorized
      }
      if (200...299).contains(response.statusCode) {
        throw APIError.malformedResponse
      }
      throw decodeRemoteError(status: response.statusCode, data: data)
    }
  }

  private func sendOKWithCSRF(
    method: String,
    request apiRequest: APIRequest,
    body: Data?
  ) async throws {
    let csrf = try validatedCSRFCookieValue(for: apiRequest)
    let mutation = try MutationRequest(
      body: body ?? Data(),
      contentType: "application/json",
      headers: ["x-fluke-csrf": csrf]
    )
    let response: StrictOKResponse = try await send(
      method: method,
      request: apiRequest,
      mutation: mutation,
      expectedStatus: 200
    )
    guard response.ok else { throw APIError.malformedResponse }
  }

  private func makeURLRequest(
    method: String,
    apiRequest: APIRequest,
    mutation: MutationRequest?
  ) throws -> URLRequest {
    let url = try apiRequest.url(relativeTo: baseURL)
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = requestTimeout.timeInterval
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let mutation {
      request.setValue(mutation.contentType, forHTTPHeaderField: "Content-Type")
      for (key, value) in mutation.headers {
        request.setValue(value, forHTTPHeaderField: key)
      }
      request.httpBody = mutation.body
    }
    applyCookies(to: &request)
    return request
  }

  private func transportData(
    for request: URLRequest,
    retriesTransientFailure: Bool
  ) async throws -> (Data, HTTPURLResponse) {
    do {
      return try await transportDataOnce(for: request)
    } catch {
      guard retriesTransientFailure, isTransientTransportFailure(error) else {
        throw error
      }
      return try await transportDataOnce(for: request)
    }
  }

  private func transportDataOnce(
    for request: URLRequest
  ) async throws -> (Data, HTTPURLResponse) {
    try await withTaskDeadline(timeout: requestTimeout) { [transport] in
      try await transport.data(for: request)
    }
  }

  private func isTransientTransportFailure(_ error: Error) -> Bool {
    guard let urlError = error as? URLError else { return false }
    return [
      .cannotConnectToHost,
      .cannotFindHost,
      .dnsLookupFailed,
      .networkConnectionLost,
      .notConnectedToInternet,
    ].contains(urlError.code)
  }

  private func applyCookies(to request: inout URLRequest) {
    guard let cookies, let url = request.url,
      let stored = cookies.cookies(for: url)
    else { return }
    let headers = HTTPCookie.requestHeaderFields(with: stored)
    request.allHTTPHeaderFields = (request.allHTTPHeaderFields ?? [:])
      .merging(headers) { _, new in new }
  }

  private func decodeRemoteError(status: Int, data: Data) -> APIError {
    if let safe = try? JSONDecoder().decode(SafeError.self, from: data),
      isBounded(safe.code, maximum: 100),
      isBounded(safe.message, maximum: 1_000),
      isBounded(safe.requestId, maximum: 200)
    {
      return .remote(
        status: status,
        code: safe.code,
        message: safe.message,
        retryable: safe.retryable,
        requestId: safe.requestId
      )
    }
    return .remote(
      status: status,
      code: "REMOTE_ERROR",
      message: "The service could not complete the request.",
      retryable: status == 408 || status == 429 || status >= 500,
      requestId: nil
    )
  }

  private func isBounded(_ value: String, maximum: Int) -> Bool {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return !normalized.isEmpty
      && normalized.count <= maximum
      && normalized.unicodeScalars.allSatisfy {
        !CharacterSet.controlCharacters.contains($0)
      }
  }
}

private struct StrictOKResponse: Decodable {
  let ok: Bool

  private enum CodingKeys: String, CodingKey, CaseIterable { case ok }

  init(from decoder: any Decoder) throws {
    let dynamic = try decoder.container(keyedBy: DynamicCodingKey.self)
    guard Set(dynamic.allKeys.map(\.stringValue)) == ["ok"] else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "Unexpected response keys")
      )
    }
    let container = try decoder.container(keyedBy: CodingKeys.self)
    guard Set(container.allKeys) == Set(CodingKeys.allCases) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "Unexpected response keys")
      )
    }
    ok = try container.decode(Bool.self, forKey: .ok)
  }
}

private struct DynamicCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int? = nil
  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { return nil }
}

extension Duration {
  fileprivate var timeInterval: TimeInterval {
    let parts = components
    return TimeInterval(parts.seconds)
      + TimeInterval(parts.attoseconds) / 1_000_000_000_000_000_000
  }
}
