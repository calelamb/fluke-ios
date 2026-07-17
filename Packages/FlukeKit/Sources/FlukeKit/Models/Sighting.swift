import Foundation

public enum SightingStatus: String, Codable, CaseIterable, Sendable {
    case pending = "PENDING"
    case approved = "APPROVED"
    case rejected = "REJECTED"
}

public enum IdentificationConfidence: String, Codable, CaseIterable, Sendable {
    case confirmed = "CONFIRMED"
    case likely = "LIKELY"
    case machineSuggested = "ML_SUGGESTED"
}

public struct SightingPhoto: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let url: String
    public let thumbnailUrl: String
    public let orderIndex: Int

    public init(id: String, url: String, thumbnailUrl: String, orderIndex: Int) {
        self.id = id
        self.url = url
        self.thumbnailUrl = thumbnailUrl
        self.orderIndex = orderIndex
    }
}

public struct IdentifiedWhale: Codable, Hashable, Sendable {
    public let catalogId: String
    public let name: String?
    public let confidence: IdentificationConfidence

    public init(catalogId: String, name: String?, confidence: IdentificationConfidence) {
        self.catalogId = catalogId
        self.name = name
        self.confidence = confidence
    }
}

/// Public, privacy-safe sighting returned by `GET /api/v1/sightings`.
public struct Sighting: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let observedAt: Date
    public let latitude: Double
    public let longitude: Double
    public let locationName: String?
    public let ecotypeGuess: Ecotype?
    public let groupSize: Int?
    public let behaviorNotes: String?
    public let status: SightingStatus
    public let photoUrls: [String]
    public let photos: [SightingPhoto]
    public let identifiedWhales: [IdentifiedWhale]

    public init(
        id: String,
        observedAt: Date,
        latitude: Double,
        longitude: Double,
        locationName: String?,
        ecotypeGuess: Ecotype?,
        groupSize: Int?,
        behaviorNotes: String?,
        status: SightingStatus,
        photoUrls: [String],
        photos: [SightingPhoto],
        identifiedWhales: [IdentifiedWhale]
    ) {
        self.id = id
        self.observedAt = observedAt
        self.latitude = latitude
        self.longitude = longitude
        self.locationName = locationName
        self.ecotypeGuess = ecotypeGuess
        self.groupSize = groupSize
        self.behaviorNotes = behaviorNotes
        self.status = status
        self.photoUrls = photoUrls
        self.photos = photos
        self.identifiedWhales = identifiedWhales
    }
}
