import Foundation

/// Minimal WhalesRepository for iOS Atlas sub-views. Will be expanded in
/// M-iOS-2 with SwiftData caching, search, and offline fallback.
public actor WhalesRepository {

    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    /// Fetch the full catalog from the live API. No caching yet.
    public func fetchAll() async throws -> [Whale] {
        let response: PaginatedResponse<Whale> = try await api.get(Endpoint.whales)
        return response.items
    }

    public func find(byId id: String) async throws -> WhaleProfile? {
        try await api.get(Endpoint.whale(id: id))
    }

    /// Fetch the per-whale movement track (used by Atlas Trace sub-view).
    public func fetchTrack(whaleId: String) async throws -> [MovementTrackPoint] {
        let response: WhaleTrack = try await api.get(Endpoint.whaleTrack(id: whaleId))
        return response.points
    }
}
