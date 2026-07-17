import Foundation

public actor SightingsRepository: SightingsRepositoryProtocol {
    private let api: APIClient
    private let loader: BrowseRepositoryLoader

    public init(api: APIClient, cache: any BrowseCacheStore = MemoryBrowseCacheStore()) {
        self.api = api
        self.loader = BrowseRepositoryLoader(cache: cache)
    }

    public func loadApproved() async throws -> BrowseResult<[Sighting]> {
        try await loader.load(
            [Sighting].self,
            key: BrowseCacheKey(resource: "sightings", identity: "approved"),
            fetch: { [api] in
                try await PaginatedRepository.fetchAll(api: api, endpoint: Endpoint.sightings)
            },
            isEmpty: { $0.isEmpty },
            validate: { try PublicBrowseValidator.sightings($0) }
        )
    }

    public func loadExternal(
        source: String? = nil,
        sinceDays: Int = 7
    ) async throws -> BrowseResult<[ExternalSighting]> {
        if let source { try BrowseRequestValidator.text(source, maximumCount: 500) }
        let boundedDays = min(max(sinceDays, 1), 31)
        let queryItems = [
            PaginationQueryItem(name: "sinceDays", value: String(boundedDays)),
            source.map { PaginationQueryItem(name: "source", value: $0) },
        ].compactMap { $0 }
        return try await loader.load(
            [ExternalSighting].self,
            key: BrowseCacheKey(
                resource: "external-sightings",
                identity: "source=\(source ?? "")&sinceDays=\(boundedDays)"
            ),
            fetch: { [api] in
                try await PaginatedRepository.fetchAll(
                    api: api,
                    endpoint: Endpoint.externalSightings,
                    queryItems: queryItems
                )
            },
            isEmpty: { $0.isEmpty },
            validate: { try PublicBrowseValidator.externalSightings($0) }
        )
    }
}
