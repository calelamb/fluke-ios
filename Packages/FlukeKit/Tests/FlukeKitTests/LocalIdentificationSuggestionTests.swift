import Foundation
import FlukeReleaseB
import Testing

@Suite("Local identification suggestion")
struct LocalIdentificationSuggestionTests {
  @Test("Accepts exact score and UTF-16 boundaries")
  func validBoundaries() throws {
    let catalogID = String(repeating: "🐋", count: 100)
    let suggestion = try #require(LocalIdentificationSuggestion(
      catalogID: catalogID,
      similarityScore: -1,
      scoreSemantics: "uncalibrated_similarity_not_probability",
      manifestVersion: "manifest-v1",
      modelVersion: "model-v1",
      indexVersion: "index-v1",
      matchedReferencePhotoIDs: ["ref-1", "ref-2"]
    ))

    #expect(suggestion.catalogID == catalogID)
    #expect(suggestion.similarityScore == -1)
  }

  @Test("Rejects malformed evidence without repairing it", arguments: [
    SuggestionInput(catalogID: " ", score: 0, semantics: Self.semantics, references: ["ref-1"]),
    SuggestionInput(catalogID: String(repeating: "a", count: 201), score: 0, semantics: Self.semantics, references: ["ref-1"]),
    SuggestionInput(catalogID: "catalog", score: .nan, semantics: Self.semantics, references: ["ref-1"]),
    SuggestionInput(catalogID: "catalog", score: 1.01, semantics: Self.semantics, references: ["ref-1"]),
    SuggestionInput(catalogID: "catalog", score: 0, semantics: "probability", references: ["ref-1"]),
    SuggestionInput(catalogID: "catalog", score: 0, semantics: Self.semantics, references: ["ref-1", "ref-1"]),
    SuggestionInput(catalogID: "catalog", score: 0, semantics: Self.semantics, references: ["1", "2", "3", "4", "5", "6"]),
    SuggestionInput(catalogID: "catalog", score: 0, semantics: Self.semantics, references: [" "]),
  ])
  func invalidEvidence(input: SuggestionInput) {
    #expect(LocalIdentificationSuggestion(
      catalogID: input.catalogID,
      similarityScore: input.score,
      scoreSemantics: input.semantics,
      manifestVersion: "manifest-v1",
      modelVersion: "model-v1",
      indexVersion: "index-v1",
      matchedReferencePhotoIDs: input.references
    ) == nil)
  }

  @Test("Codable uses the exact API field names and preserves reference order")
  func exactCodableShape() throws {
    let suggestion = try #require(Self.validSuggestion)
    let data = try JSONEncoder().encode(suggestion)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(Set(json.keys) == [
      "catalogId", "similarityScore", "scoreSemantics", "manifestVersion", "modelVersion",
      "indexVersion", "matchedReferencePhotoIds",
    ])
    #expect(json["matchedReferencePhotoIds"] as? [String] == ["ref-2", "ref-1"])
    #expect(try JSONDecoder().decode(LocalIdentificationSuggestion.self, from: data) == suggestion)
  }

  @Test("Invalid queued nested evidence degrades to nil without losing the wildlife payload")
  func invalidQueuedEvidenceIsLossyOptional() throws {
    let payload = SubmissionPayload(
      clientSubmissionID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
      latitude: 48.5,
      longitude: -123.1,
      observedAt: Date(timeIntervalSince1970: 1_700_000_000),
      groupSize: 3,
      notes: nil,
      locationName: nil,
      observerEmail: "observer@example.com",
      photoCount: 1,
      ecotypeGuess: .biggs,
      localIdentification: Self.validSuggestion
    )
    let encoded = try JSONEncoder().encode(payload)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    var evidence = try #require(object["local_identification"] as? [String: Any])
    evidence["similarityScore"] = 2
    object["local_identification"] = evidence

    let corrupted = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(SubmissionPayload.self, from: corrupted)

    #expect(decoded.clientSubmissionID == payload.clientSubmissionID)
    #expect(decoded.ecotypeGuess == .biggs)
    #expect(decoded.localIdentification == nil)
  }

  @Test("Partial retry and account unlink preserve immutable evidence and submission identity")
  func payloadTransformationsPreserveEvidence() throws {
    let suggestion = try #require(Self.validSuggestion)
    let payload = SubmissionPayload(
      latitude: 48.5,
      longitude: -123.1,
      observedAt: Date(timeIntervalSince1970: 1_700_000_000),
      groupSize: 3,
      notes: nil,
      locationName: nil,
      observerEmail: "observer@example.com",
      photoCount: 1,
      ecotypeGuess: .biggs,
      localIdentification: suggestion
    )
    let resumed = payload.resuming(receipt: .init(id: "created", photoUploadToken: "token"))
    let unlinked = resumed.removingObserverEmail()

    #expect(unlinked.clientSubmissionID == payload.clientSubmissionID)
    #expect(unlinked.ecotypeGuess == .biggs)
    #expect(unlinked.localIdentification == suggestion)
    #expect(unlinked.observerEmail == nil)
  }

  private static let semantics = "uncalibrated_similarity_not_probability"
  private static var validSuggestion: LocalIdentificationSuggestion? {
    LocalIdentificationSuggestion(
      catalogID: "catalog-1",
      similarityScore: 0.75,
      scoreSemantics: semantics,
      manifestVersion: "manifest-v1",
      modelVersion: "model-v1",
      indexVersion: "index-v1",
      matchedReferencePhotoIDs: ["ref-2", "ref-1"]
    )
  }
}

struct SuggestionInput: Sendable, CustomTestStringConvertible {
  let catalogID: String
  let score: Double
  let semantics: String
  let references: [String]

  var testDescription: String { "\(catalogID)-\(score)-\(semantics)-\(references.count)" }
}
