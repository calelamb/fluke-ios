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
        var queryItems: [(name: String, value: String)] = []
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let from { queryItems.append((name: "from", value: isoFormatter.string(from: from))) }
        if let to   { queryItems.append((name: "to", value: isoFormatter.string(from: to))) }
        if let pod  { queryItems.append((name: "pod", value: pod.rawValue)) }
        if let whaleId { queryItems.append((name: "whaleId", value: whaleId)) }

        var path = Endpoint.historicalSightings
        if !queryItems.isEmpty {
            let allowed = CharacterSet.urlQueryAllowed
            path += "?" + queryItems
                .map { "\($0.name)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
                .joined(separator: "&")
        }
        let response: PaginatedResponse<HistoricalSighting> = try await api.get(path)
        return response.items
    }
}
