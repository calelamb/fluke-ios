import Foundation

public enum IdentifyConfidenceBand: String, Codable, CaseIterable, Sendable {
    case high
    case medium
    case low
    case unavailable
}

public struct IdentifyMatch: Codable, Hashable, Sendable {
    public let catalogId: String
    public let name: String?
    public let score: Double
    public let rank: Int
    public let matchedReferencePhotoIds: [String]
    public let explanation: String
}

public struct IdentifyResponse: Codable, Hashable, Sendable {
    public let matches: [IdentifyMatch]
    public let confidenceBand: IdentifyConfidenceBand
    public let model: String
    public let indexVersion: String
    public let uploadURL: String?

    private enum CodingKeys: String, CodingKey {
        case matches
        case confidenceBand
        case model
        case indexVersion
        case uploadURL = "uploadUrl"
    }
}
