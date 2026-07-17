import Foundation

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
        requestTimeout: Duration = APIClient.defaultRequestTimeout
    ) {
        self.init(
            baseURL: baseURL,
            transport: transport,
            requestTimeout: requestTimeout,
            cookies: nil
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
        return try await get(APIRequest(
            path: components.path,
            queryItems: components.queryItems ?? []
        ))
    }

    public func get<T: Decodable>(_ apiRequest: APIRequest) async throws -> T {
        try await send(method: "GET", request: apiRequest, mutation: nil)
    }

    public func post<Request: Encodable & Sendable, Response: Decodable>(
        _ request: APIRequest,
        body: Request
    ) async throws -> Response {
        let encodedBody: Data
        do {
            encodedBody = try JSONEncoder().encode(body)
        } catch {
            throw APIError.invalidRequest
        }
        let mutation = try MutationRequest(
            body: encodedBody,
            contentType: "application/json"
        )
        return try await send(
            method: "POST",
            request: request,
            mutation: mutation,
            retriesTransientFailure: true
        )
    }

    public func postMultipart<Response: Decodable>(
        _ request: APIRequest,
        parts: [MultipartPart],
        headers: [String: String] = [:]
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
            retriesTransientFailure: true
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

    public func clearCookies() {
        guard let cookies, let host = baseURL.host?.lowercased() else { return }
        cookies.cookies?
            .filter { cookie in
                cookie.domain
                    .lowercased()
                    .trimmingCharacters(in: CharacterSet(charactersIn: ".")) == host
            }
            .forEach(cookies.deleteCookie)
    }

    private func send<T: Decodable>(
        method: String,
        request apiRequest: APIRequest,
        mutation: MutationRequest?,
        retriesTransientFailure: Bool = false
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
            mutation.headers.forEach { key, value in
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
              let stored = cookies.cookies(for: url) else { return }
        let headers = HTTPCookie.requestHeaderFields(with: stored)
        request.allHTTPHeaderFields = (request.allHTTPHeaderFields ?? [:])
            .merging(headers) { _, new in new }
    }

    private func decodeRemoteError(status: Int, data: Data) -> APIError {
        if let safe = try? JSONDecoder().decode(SafeError.self, from: data),
           isBounded(safe.code, maximum: 100),
           isBounded(safe.message, maximum: 1_000),
           isBounded(safe.requestId, maximum: 200) {
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

private extension Duration {
    var timeInterval: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds)
            + TimeInterval(parts.attoseconds) / 1_000_000_000_000_000_000
    }
}
