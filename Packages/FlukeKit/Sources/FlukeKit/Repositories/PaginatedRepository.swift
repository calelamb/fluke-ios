import Foundation

struct PaginationQueryItem: Sendable {
    let name: String
    let value: String
}

enum PaginatedRepository {
    static let maximumPageCount = 100

    static func fetchAll<Item: Codable & Hashable & Sendable>(
        api: APIClient,
        endpoint: String,
        queryItems: [PaginationQueryItem] = []
    ) async throws -> [Item] {
        try await fetchAll(
            api: api,
            endpoint: endpoint,
            queryItems: queryItems,
            cursor: nil,
            seenCursors: [],
            fetchedPageCount: 0,
            accumulatedItems: []
        )
    }

    private static func fetchAll<Item: Codable & Hashable & Sendable>(
        api: APIClient,
        endpoint: String,
        queryItems: [PaginationQueryItem],
        cursor: String?,
        seenCursors: Set<String>,
        fetchedPageCount: Int,
        accumulatedItems: [Item]
    ) async throws -> [Item] {
        guard fetchedPageCount < maximumPageCount else {
            throw APIError.invalidPagination
        }

        let path = try requestPath(endpoint: endpoint, queryItems: queryItems, cursor: cursor)
        let response: PaginatedResponse<Item> = try await api.get(path)
        let allItems = accumulatedItems + response.items
        guard response.page.hasMore else {
            return allItems
        }
        guard let nextCursor = response.page.nextCursor,
              !nextCursor.isEmpty,
              !seenCursors.contains(nextCursor) else {
            throw APIError.invalidPagination
        }

        return try await fetchAll(
            api: api,
            endpoint: endpoint,
            queryItems: queryItems,
            cursor: nextCursor,
            seenCursors: seenCursors.union([nextCursor]),
            fetchedPageCount: fetchedPageCount + 1,
            accumulatedItems: allItems
        )
    }

    private static func requestPath(
        endpoint: String,
        queryItems: [PaginationQueryItem],
        cursor: String?
    ) throws -> String {
        let cursorItems = cursor.map { [PaginationQueryItem(name: "cursor", value: $0)] } ?? []
        let allQueryItems = queryItems + cursorItems
        guard !allQueryItems.isEmpty else {
            return endpoint
        }

        let encodedItems = try allQueryItems.map { item in
            guard let name = encodeQueryComponent(item.name),
                  let value = encodeQueryComponent(item.value) else {
                throw APIError.invalidPagination
            }
            return "\(name)=\(value)"
        }
        return "\(endpoint)?\(encodedItems.joined(separator: "&"))"
    }

    private static func encodeQueryComponent(_ component: String) -> String? {
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return component.addingPercentEncoding(withAllowedCharacters: unreserved)
    }
}
