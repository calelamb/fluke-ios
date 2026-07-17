import Foundation

public enum WhaleSex: String, Codable, CaseIterable, Sendable {
    case male = "MALE"
    case female = "FEMALE"
    case unknown = "UNKNOWN"
}

public enum WhaleStatus: String, Codable, CaseIterable, Sendable {
    case alive = "ALIVE"
    case deceased = "DECEASED"
    case unknown = "UNKNOWN"
}

public struct Whale: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let catalogId: String
    public let name: String?
    public let ecotype: Ecotype
    public let pod: String?
    public let sex: WhaleSex
    public let birthYear: Int?
    public let deathYear: Int?
    public let status: WhaleStatus
    public let biography: String?
    public let distinguishingMarks: String?
    public let heroImageUrl: String?
    public let notableEvents: [NotableEvent]
    public let sourceCitations: [SourceCitation]

    public init(
        id: String,
        catalogId: String,
        name: String?,
        ecotype: Ecotype,
        pod: String?,
        sex: WhaleSex,
        birthYear: Int?,
        deathYear: Int?,
        status: WhaleStatus,
        biography: String?,
        distinguishingMarks: String?,
        heroImageUrl: String?,
        notableEvents: [NotableEvent],
        sourceCitations: [SourceCitation]
    ) {
        self.id = id
        self.catalogId = catalogId
        self.name = name
        self.ecotype = ecotype
        self.pod = pod
        self.sex = sex
        self.birthYear = birthYear
        self.deathYear = deathYear
        self.status = status
        self.biography = biography
        self.distinguishingMarks = distinguishingMarks
        self.heroImageUrl = heroImageUrl
        self.notableEvents = notableEvents
        self.sourceCitations = sourceCitations
    }
}
