import Foundation

/// A small typed HTTP client over `URLSession`. Cookies are persisted via
/// the session's `httpCookieStorage`, matching the cookie-based auth the
/// Fluke API uses for both admin and (incoming) observer sessions.
public final class APIClient {

    public let baseURL: URL
    public let session: URLSession

    /// Shorthand for the session's cookie storage. Tests inject cookies here.
    public var cookieStorage: HTTPCookieStorage {
        session.configuration.httpCookieStorage ?? HTTPCookieStorage.shared
    }

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func get<T: Decodable>(_ path: String) async throws -> T {
        try await send(method: "GET", path: path, body: nil)
    }

    public func post<T: Decodable, B: Encodable>(
        _ path: String,
        body: B
    ) async throws -> T {
        let data = try JSONEncoder().encode(body)
        return try await send(method: "POST", path: path, body: data)
    }

    public func postEmpty<T: Decodable>(_ path: String) async throws -> T {
        try await send(method: "POST", path: path, body: nil)
    }

    private func send<T: Decodable>(
        method: String,
        path: String,
        body: Data?
    ) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.unknown
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        // Manually apply cookies from storage to request
        let storage = cookieStorage
        if let cookies = storage.cookies(for: url) {
            let headers = HTTPCookie.requestHeaderFields(with: cookies)
            request.allHTTPHeaderFields = (request.allHTTPHeaderFields ?? [:]).merging(headers) { _, new in new }
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.unknown
        }

        switch http.statusCode {
        case 200...299:
            do {
                return try JSONDecoder.fluke.decode(T.self, from: data)
            } catch {
                throw APIError.decoding(String(describing: T.self))
            }
        case 401:
            throw APIError.unauthorized
        default:
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw APIError.server(status: http.statusCode, body: bodyStr)
        }
    }
}
