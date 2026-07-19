import Foundation

public struct LocalIdentificationSuggestion: Codable, Hashable, Sendable {
  public static let requiredScoreSemantics = "uncalibrated_similarity_not_probability"

  public let catalogID: String
  public let similarityScore: Double
  public let scoreSemantics: String
  public let manifestVersion: String
  public let modelVersion: String
  public let indexVersion: String
  public let matchedReferencePhotoIDs: [String]

  public init?(
    catalogID: String,
    similarityScore: Double,
    scoreSemantics: String,
    manifestVersion: String,
    modelVersion: String,
    indexVersion: String,
    matchedReferencePhotoIDs: [String]
  ) {
    guard Self.isStableID(catalogID), similarityScore.isFinite,
      (-1...1).contains(similarityScore),
      scoreSemantics == Self.requiredScoreSemantics,
      Self.isStableID(manifestVersion), Self.isStableID(modelVersion),
      Self.isStableID(indexVersion), matchedReferencePhotoIDs.count <= 5,
      Set(matchedReferencePhotoIDs).count == matchedReferencePhotoIDs.count,
      matchedReferencePhotoIDs.allSatisfy(Self.isStableID)
    else { return nil }

    self.catalogID = catalogID
    self.similarityScore = similarityScore
    self.scoreSemantics = scoreSemantics
    self.manifestVersion = manifestVersion
    self.modelVersion = modelVersion
    self.indexVersion = indexVersion
    self.matchedReferencePhotoIDs = matchedReferencePhotoIDs
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    guard let value = Self(
      catalogID: try values.decode(String.self, forKey: .catalogID),
      similarityScore: try values.decode(Double.self, forKey: .similarityScore),
      scoreSemantics: try values.decode(String.self, forKey: .scoreSemantics),
      manifestVersion: try values.decode(String.self, forKey: .manifestVersion),
      modelVersion: try values.decode(String.self, forKey: .modelVersion),
      indexVersion: try values.decode(String.self, forKey: .indexVersion),
      matchedReferencePhotoIDs: try values.decode([String].self, forKey: .matchedReferencePhotoIDs)
    ) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "Invalid local identification evidence")
      )
    }
    self = value
  }

  private static func isStableID(_ value: String) -> Bool {
    (1...200).contains(value.utf16.count)
      && value.contains(where: { !$0.isWhitespace })
  }

  enum CodingKeys: String, CodingKey {
    case catalogID = "catalogId"
    case similarityScore
    case scoreSemantics
    case manifestVersion
    case modelVersion
    case indexVersion
    case matchedReferencePhotoIDs = "matchedReferencePhotoIds"
  }
}
