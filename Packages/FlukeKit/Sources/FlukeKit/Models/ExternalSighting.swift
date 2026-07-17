import Foundation

public struct ExternalSighting: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let source: String
    public let externalId: String
    public let observedAt: Date
    public let latitude: Double
    public let longitude: Double
    public let species: String
    public let ecotypeGuess: Ecotype?
    public let groupSize: Int?
    public let attribution: String
    public let sourceURL: String?
    public let notes: String?
    public let trusted: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case source
        case externalId
        case observedAt
        case latitude
        case longitude
        case species
        case ecotypeGuess
        case groupSize
        case attribution
        case sourceURL = "sourceUrl"
        case notes
        case trusted
    }
}
