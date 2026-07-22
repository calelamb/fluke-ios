import Foundation

public struct APIRequest: Hashable, Sendable {
    public let path: String
    public let queryItems: [URLQueryItem]

    public init(path: String, queryItems: [URLQueryItem] = []) {
        self.path = path
        self.queryItems = queryItems
    }

    public func url(relativeTo baseURL: URL, pathPrefix: String = "") throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.malformedResponse
        }
        guard path.hasPrefix("/"), !path.contains("?"), !path.contains("#"),
              isValidPrefix(pathPrefix) else {
            throw APIError.invalidRequest
        }
        let routedPath = try routedPath(pathPrefix: pathPrefix)
        components.percentEncodedPath = try routedPath
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { segment in
                guard segment != ".", segment != ".." else {
                    throw APIError.invalidRequest
                }
                guard let encoded = Self.encode(String(segment)) else {
                    throw APIError.invalidRequest
                }
                return encoded
            }
            .joined(separator: "/")
        components.percentEncodedQuery = queryItems.isEmpty ? nil : try queryItems
            .map { item in
                guard let name = Self.encode(item.name),
                      let value = Self.encode(item.value ?? "") else {
                    throw APIError.malformedResponse
                }
                return "\(name)=\(value)"
            }
            .joined(separator: "&")
        guard let url = components.url else {
            throw APIError.malformedResponse
        }
        return url
    }

    private func isValidPrefix(_ prefix: String) -> Bool {
        guard prefix.isEmpty || prefix.hasPrefix("/") else { return false }
        guard !prefix.hasSuffix("/"), !prefix.contains("?"), !prefix.contains("#") else {
            return false
        }
        return prefix.split(separator: "/").allSatisfy { $0 != "." && $0 != ".." }
    }

    private func routedPath(pathPrefix: String) throws -> String {
        guard !pathPrefix.isEmpty else { return path }
        guard path == "/api" || path.hasPrefix("/api/") else {
            throw APIError.invalidRequest
        }
        return "\(pathPrefix)\(path.dropFirst(4))"
    }

    private static func encode(_ component: String) -> String? {
        let unreserved = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-._~")
        )
        return component.addingPercentEncoding(withAllowedCharacters: unreserved)
    }
}
