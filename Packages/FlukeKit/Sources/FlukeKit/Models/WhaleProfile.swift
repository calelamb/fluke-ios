import Foundation

public struct WhaleRelation: Codable, Hashable, Sendable {
    public let catalogId: String
    public let name: String?

    public init(catalogId: String, name: String?) {
        self.catalogId = catalogId
        self.name = name
    }
}

public struct RecentSighting: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let observedAt: Date
    public let locationName: String?
    public let latitude: Double
    public let longitude: Double

    public init(
        id: String,
        observedAt: Date,
        locationName: String?,
        latitude: Double,
        longitude: Double
    ) {
        self.id = id
        self.observedAt = observedAt
        self.locationName = locationName
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct WhaleProfile: Codable, Hashable, Sendable, Identifiable {
    public let whale: Whale
    public let mother: WhaleRelation?
    public let offspring: [WhaleRelation]
    public let recentSightings: [RecentSighting]

    public var id: String { whale.id }
    public var catalogId: String { whale.catalogId }
    public var name: String? { whale.name }

    public init(
        whale: Whale,
        mother: WhaleRelation?,
        offspring: [WhaleRelation],
        recentSightings: [RecentSighting]
    ) {
        self.whale = whale
        self.mother = mother
        self.offspring = offspring
        self.recentSightings = recentSightings
    }

    private enum CodingKeys: String, CodingKey {
        case mother
        case offspring
        case recentSightings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.whale = try Whale(from: decoder)
        self.mother = try container.decodeIfPresent(WhaleRelation.self, forKey: .mother)
        self.offspring = try container.decode([WhaleRelation].self, forKey: .offspring)
        self.recentSightings = try container.decode([RecentSighting].self, forKey: .recentSightings)
    }

    public func encode(to encoder: Encoder) throws {
        try whale.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(mother, forKey: .mother)
        try container.encode(offspring, forKey: .offspring)
        try container.encode(recentSightings, forKey: .recentSightings)
    }
}
