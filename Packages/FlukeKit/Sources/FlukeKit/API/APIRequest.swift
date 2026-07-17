import Foundation

public struct APIRequest: Hashable, Sendable {
    public let path: String
    public let queryItems: [URLQueryItem]

    public init(path: String, queryItems: [URLQueryItem] = []) {
        self.path = path
        self.queryItems = queryItems
    }

    public func url(relativeTo baseURL: URL) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.malformedResponse
        }
        components.path = path
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

    private static func encode(_ component: String) -> String? {
        let unreserved = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-._~")
        )
        return component.addingPercentEncoding(withAllowedCharacters: unreserved)
    }
}
