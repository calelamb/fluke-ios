import Foundation

public struct HistoricalSighting: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let observedAt: Date
    public let latitude: Double
    public let longitude: Double
    public let locationName: String?
    public let ecotypeGuess: Ecotype?
    public let whaleIds: [String]

    public init(
        id: String,
        observedAt: Date,
        latitude: Double,
        longitude: Double,
        locationName: String?,
        ecotypeGuess: Ecotype?,
        whaleIds: [String]
    ) {
        self.id = id
        self.observedAt = observedAt
        self.latitude = latitude
        self.longitude = longitude
        self.locationName = locationName
        self.ecotypeGuess = ecotypeGuess
        self.whaleIds = whaleIds
    }
}
