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

  public init(
    catalogId: String,
    name: String?,
    score: Double,
    rank: Int,
    matchedReferencePhotoIds: [String],
    explanation: String
  ) {
    self.catalogId = catalogId
    self.name = name
    self.score = score
    self.rank = rank
    self.matchedReferencePhotoIds = matchedReferencePhotoIds
    self.explanation = explanation
  }
}

public struct IdentifyResponse: Codable, Hashable, Sendable {
  public let matches: [IdentifyMatch]
  public let confidenceBand: IdentifyConfidenceBand
  public let model: String
  public let indexVersion: String
  public let uploadURL: String?

  public init(
    matches: [IdentifyMatch],
    confidenceBand: IdentifyConfidenceBand,
    model: String,
    indexVersion: String,
    uploadURL: String?
  ) {
    self.matches = matches
    self.confidenceBand = confidenceBand
    self.model = model
    self.indexVersion = indexVersion
    self.uploadURL = uploadURL
  }

  private enum CodingKeys: String, CodingKey {
    case matches
    case confidenceBand
    case model
    case indexVersion
    case uploadURL = "uploadUrl"
  }
}
