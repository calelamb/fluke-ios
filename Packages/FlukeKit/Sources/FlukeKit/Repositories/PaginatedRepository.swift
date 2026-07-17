import Foundation

struct PaginationQueryItem: Sendable {
    let name: String
    let value: String
}

enum PaginatedRepository {
    static let maximumPageCount = 100
    static let maximumItemCount = 10_000
    static let defaultOperationTimeout: Duration = .seconds(30)

    static func fetchAll<Item: Codable & Hashable & Sendable>(
        api: APIClient,
        endpoint: String,
        queryItems: [PaginationQueryItem] = [],
        operationTimeout: Duration = defaultOperationTimeout
    ) async throws -> [Item] {
        try await withTaskDeadline(timeout: operationTimeout) {
            try await fetchPages(api: api, endpoint: endpoint, queryItems: queryItems)
        }
    }

    private static func fetchPages<Item: Codable & Hashable & Sendable>(
        api: APIClient,
        endpoint: String,
        queryItems: [PaginationQueryItem]
    ) async throws -> [Item] {
        var cursor: String?
        var seenCursors: Set<String> = []
        var fetchedPageCount = 0
        var accumulatedItems: [Item] = []

        while true {
            try Task.checkCancellation()
            guard fetchedPageCount < maximumPageCount else {
                throw APIError.invalidPagination
            }
            let path = try requestPath(endpoint: endpoint, queryItems: queryItems, cursor: cursor)
            let response: PaginatedResponse<Item> = try await api.get(path)
            try Task.checkCancellation()
            guard response.items.count <= maximumItemCount - accumulatedItems.count else {
                throw APIError.invalidPagination
            }
            accumulatedItems.append(contentsOf: response.items)
            try Task.checkCancellation()

            if !response.page.hasMore {
                guard response.page.nextCursor == nil else {
                    throw APIError.invalidPagination
                }
                try Task.checkCancellation()
                return accumulatedItems
            }
            guard let nextCursor = response.page.nextCursor,
                  !nextCursor.isEmpty,
                  !seenCursors.contains(nextCursor) else {
                throw APIError.invalidPagination
            }
            seenCursors.insert(nextCursor)
            cursor = nextCursor
            fetchedPageCount += 1
        }
    }

    private static func requestPath(
        endpoint: String,
        queryItems: [PaginationQueryItem],
        cursor: String?
    ) throws -> String {
        let cursorItems = cursor.map { [PaginationQueryItem(name: "cursor", value: $0)] } ?? []
        let allQueryItems = queryItems + cursorItems
        guard !allQueryItems.isEmpty else { return endpoint }

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
