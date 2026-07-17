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
        try await send(method: "GET", request: apiRequest, body: nil)
    }

    private func send<T: Decodable>(
        method: String,
        request apiRequest: APIRequest,
        body: Data?
    ) async throws -> T {
        let url = try apiRequest.url(relativeTo: baseURL)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = requestTimeout.timeInterval
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        applyCookies(to: &request)

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transportData(for: request)
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

    private func transportData(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await withTaskDeadline(timeout: requestTimeout) { [transport] in
            try await transport.data(for: request)
        }
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
