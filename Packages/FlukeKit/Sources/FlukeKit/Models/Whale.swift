import Foundation

public struct Whale: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let catalogId: String
    public let name: String?
    public let ecotype: Ecotype
    public let pod: String?
    public let biography: String?
    public let heroImageUrl: String?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: String,
        catalogId: String,
        name: String?,
        ecotype: Ecotype,
        pod: String?,
        biography: String?,
        heroImageUrl: String?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.catalogId = catalogId
        self.name = name
        self.ecotype = ecotype
        self.pod = pod
        self.biography = biography
        self.heroImageUrl = heroImageUrl
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
