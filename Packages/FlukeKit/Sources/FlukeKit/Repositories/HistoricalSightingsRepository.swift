import Foundation

public actor HistoricalSightingsRepository {

    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func fetch(
        from: Date? = nil,
        to: Date? = nil,
        pod: Pod? = nil,
        whaleId: String? = nil
    ) async throws -> [HistoricalSighting] {
        let isoFormatter = ISO8601DateFormatter()
        let queryItems: [PaginationQueryItem] = [
            from.map { PaginationQueryItem(name: "from", value: isoFormatter.string(from: $0)) },
            to.map { PaginationQueryItem(name: "to", value: isoFormatter.string(from: $0)) },
            pod.map { PaginationQueryItem(name: "pod", value: $0.rawValue) },
            whaleId.map { PaginationQueryItem(name: "whaleId", value: $0) },
        ].compactMap { $0 }

        return try await PaginatedRepository.fetchAll(
            api: api,
            endpoint: Endpoint.historicalSightings,
            queryItems: queryItems
        )
    }
}
