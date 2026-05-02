import Foundation

public struct MovementTrackPoint: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let observedAt: Date
    public let latitude: Double
    public let longitude: Double
    public let locationName: String?
    public let behaviorNotes: String?

    public init(
        id: String,
        observedAt: Date,
        latitude: Double,
        longitude: Double,
        locationName: String?,
        behaviorNotes: String?
    ) {
        self.id = id
        self.observedAt = observedAt
        self.latitude = latitude
        self.longitude = longitude
        self.locationName = locationName
        self.behaviorNotes = behaviorNotes
    }
}
