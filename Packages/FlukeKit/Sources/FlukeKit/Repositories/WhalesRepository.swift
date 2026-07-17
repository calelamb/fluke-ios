import Foundation

/// Network-first public whale data with validated last-known-good fallback.
public actor WhalesRepository: WhalesRepositoryProtocol {

    private let api: APIClient
    private let loader: BrowseRepositoryLoader

    public init(api: APIClient, cache: any BrowseCacheStore = MemoryBrowseCacheStore()) {
        self.api = api
        self.loader = BrowseRepositoryLoader(cache: cache)
    }

    public func loadCatalog() async throws -> BrowseResult<[Whale]> {
        return try await loader.load(
            [Whale].self,
            key: BrowseCacheKey(resource: "whales", identity: "catalog"),
            fetch: { [api] in
                try await PaginatedRepository.fetchAll(api: api, endpoint: Endpoint.whales)
            },
            isEmpty: { $0.isEmpty },
            validate: { try PublicBrowseValidator.whales($0) }
        )
    }

    /// Compatibility API for callers that need a throwing live-only fetch.
    public func fetchAll() async throws -> [Whale] {
        let values: [Whale] = try await PaginatedRepository.fetchAll(api: api, endpoint: Endpoint.whales)
        try PublicBrowseValidator.whales(values)
        return values
    }

    public func loadProfile(id: String) async throws -> BrowseResult<WhaleProfile?> {
        try BrowseRequestValidator.identifier(id, pathSegment: true)
        return try await loader.load(
            WhaleProfile?.self,
            key: BrowseCacheKey(resource: "whale-profile", identity: id),
            fetch: { [api] in
                do {
                    return try await api.get(try Endpoint.whale(id: id))
                } catch APIError.remote(status: 404, code: _, message: _, retryable: _, requestId: _) {
                    return nil
                }
            },
            isEmpty: { $0 == nil },
            validate: { profile in
                if let profile {
                    try PublicBrowseValidator.whaleProfile(profile, requestedID: id)
                }
            }
        )
    }

    public func find(byId id: String) async throws -> WhaleProfile? {
        try BrowseRequestValidator.identifier(id, pathSegment: true)
        let profile: WhaleProfile = try await api.get(try Endpoint.whale(id: id))
        try PublicBrowseValidator.whaleProfile(profile, requestedID: id)
        return profile
    }

    public func loadTrack(
        whaleId: String,
        from: Date,
        to: Date
    ) async throws -> BrowseResult<[MovementTrackPoint]> {
        try BrowseRequestValidator.identifier(whaleId, pathSegment: true)
        try BrowseRequestValidator.dateWindow(from: from, to: to)
        let query = trackQuery(from: from, to: to)
        return try await loader.load(
            [MovementTrackPoint].self,
            key: BrowseCacheKey(resource: "whale-track", identity: "\(whaleId)|\(query.identity)"),
            fetch: { [api] in
                let response: WhaleTrack = try await api.get(APIRequest(
                    path: try Endpoint.whaleTrack(id: whaleId),
                    queryItems: query.items
                ))
                try PublicBrowseValidator.whaleTrack(response, requestedID: whaleId)
                return response.points
            },
            isEmpty: { $0.isEmpty },
            validate: { try PublicBrowseValidator.track($0) }
        )
    }

    /// Fetch the per-whale movement track (used by Atlas Trace sub-view).
    public func fetchTrack(whaleId: String, from: Date, to: Date) async throws -> [MovementTrackPoint] {
        try BrowseRequestValidator.identifier(whaleId, pathSegment: true)
        try BrowseRequestValidator.dateWindow(from: from, to: to)
        let query = trackQuery(from: from, to: to)
        let response: WhaleTrack = try await api.get(APIRequest(
            path: try Endpoint.whaleTrack(id: whaleId),
            queryItems: query.items
        ))
        try PublicBrowseValidator.whaleTrack(response, requestedID: whaleId)
        return response.points
    }

    private func trackQuery(from: Date, to: Date) -> (identity: String, items: [URLQueryItem]) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fromValue = formatter.string(from: from)
        let toValue = formatter.string(from: to)
        return (
            "from=\(fromValue)&to=\(toValue)",
            [URLQueryItem(name: "from", value: fromValue), URLQueryItem(name: "to", value: toValue)]
        )
    }
}
