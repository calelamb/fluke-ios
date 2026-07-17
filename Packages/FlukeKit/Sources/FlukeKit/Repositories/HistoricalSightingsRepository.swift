import Foundation

public actor HistoricalSightingsRepository: HistoricalSightingsRepositoryProtocol {

    private let api: APIClient
    private let loader: BrowseRepositoryLoader

    public init(api: APIClient, cache: any BrowseCacheStore = MemoryBrowseCacheStore()) {
        self.api = api
        self.loader = BrowseRepositoryLoader(cache: cache)
    }

    public func load(
        from: Date,
        to: Date,
        pod: Pod? = nil
    ) async throws -> BrowseResult<[HistoricalSighting]> {
        let queryItems = makeQueryItems(from: from, to: to, pod: pod, whaleId: nil)
        let identity = queryItems.map { "\($0.name)=\($0.value)" }.joined(separator: "&")
        return try await loader.load(
            [HistoricalSighting].self,
            key: BrowseCacheKey(resource: "historical-sightings", identity: identity),
            fetch: { [api] in
                try await PaginatedRepository.fetchAll(
                    api: api,
                    endpoint: Endpoint.historicalSightings,
                    queryItems: queryItems
                )
            },
            isEmpty: { $0.isEmpty },
            validate: { try PublicBrowseValidator.historicalSightings($0) }
        )
    }

    public func fetch(
        from: Date? = nil,
        to: Date? = nil,
        pod: Pod? = nil,
        whaleId: String? = nil
    ) async throws -> [HistoricalSighting] {
        let queryItems = makeQueryItems(from: from, to: to, pod: pod, whaleId: whaleId)

        let values: [HistoricalSighting] = try await PaginatedRepository.fetchAll(
            api: api,
            endpoint: Endpoint.historicalSightings,
            queryItems: queryItems
        )
        try PublicBrowseValidator.historicalSightings(values)
        return values
    }

    private func makeQueryItems(
        from: Date?,
        to: Date?,
        pod: Pod?,
        whaleId: String?
    ) -> [PaginationQueryItem] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return [
            from.map { PaginationQueryItem(name: "from", value: formatter.string(from: $0)) },
            to.map { PaginationQueryItem(name: "to", value: formatter.string(from: $0)) },
            pod.map { PaginationQueryItem(name: "pod", value: $0.rawValue) },
            whaleId.map { PaginationQueryItem(name: "whaleId", value: $0) },
        ].compactMap { $0 }
    }
}
