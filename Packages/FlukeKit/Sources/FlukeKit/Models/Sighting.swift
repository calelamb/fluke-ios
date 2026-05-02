import Foundation

public enum SightingStatus: String, Codable, Sendable {
    case pending  = "PENDING"
    case approved = "APPROVED"
    case rejected = "REJECTED"
}

public struct Sighting: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let observedAt: Date
    public let latitude: Double
    public let longitude: Double
    public let locationName: String?
    public let ecotypeGuess: Ecotype?
    public let groupSize: Int?
    public let behaviorNotes: String?
    public let observerEmail: String
    public let status: SightingStatus
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, observedAt, latitude, longitude, locationName,
             ecotypeGuess, groupSize, behaviorNotes, observerEmail,
             status, createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.observedAt = try c.decode(Date.self, forKey: .observedAt)
        // Prisma serializes Decimal as string. Tolerate both.
        self.latitude = try Self.decodeDouble(c, .latitude)
        self.longitude = try Self.decodeDouble(c, .longitude)
        self.locationName = try c.decodeIfPresent(String.self, forKey: .locationName)
        self.ecotypeGuess = try c.decodeIfPresent(Ecotype.self, forKey: .ecotypeGuess)
        self.groupSize = try c.decodeIfPresent(Int.self, forKey: .groupSize)
        self.behaviorNotes = try c.decodeIfPresent(String.self, forKey: .behaviorNotes)
        self.observerEmail = try c.decode(String.self, forKey: .observerEmail)
        self.status = try c.decode(SightingStatus.self, forKey: .status)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(observedAt, forKey: .observedAt)
        try c.encode(latitude, forKey: .latitude)
        try c.encode(longitude, forKey: .longitude)
        try c.encodeIfPresent(locationName, forKey: .locationName)
        try c.encodeIfPresent(ecotypeGuess, forKey: .ecotypeGuess)
        try c.encodeIfPresent(groupSize, forKey: .groupSize)
        try c.encodeIfPresent(behaviorNotes, forKey: .behaviorNotes)
        try c.encode(observerEmail, forKey: .observerEmail)
        try c.encode(status, forKey: .status)
        try c.encode(createdAt, forKey: .createdAt)
    }

    private static func decodeDouble(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys
    ) throws -> Double {
        if let d = try? container.decode(Double.self, forKey: key) { return d }
        if let s = try? container.decode(String.self, forKey: key), let d = Double(s) { return d }
        throw DecodingError.dataCorruptedError(
            forKey: key, in: container,
            debugDescription: "Expected Double or numeric String"
        )
    }
}
