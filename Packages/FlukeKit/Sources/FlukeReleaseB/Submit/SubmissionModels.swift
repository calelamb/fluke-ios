import FlukeKit
import Foundation

public struct SubmissionDraft: Hashable, Sendable {
  public let latitude: Double
  public let longitude: Double
  public let observedAt: Date
  public let groupSize: Int
  public let notes: String?
  public let locationName: String?
  public let observerEmail: String?
  public let photoCount: Int
  public let clientSubmissionID: UUID
  public let ecotypeGuess: Ecotype?
  public let localIdentification: LocalIdentificationSuggestion?

  public init(
    latitude: Double,
    longitude: Double,
    observedAt: Date,
    groupSize: Int,
    notes: String? = nil,
    locationName: String? = nil,
    observerEmail: String? = nil,
    photoCount: Int,
    clientSubmissionID: UUID = UUID(),
    ecotypeGuess: Ecotype? = nil,
    localIdentification: LocalIdentificationSuggestion? = nil
  ) {
    self.latitude = latitude
    self.longitude = longitude
    self.observedAt = observedAt
    self.groupSize = groupSize
    self.notes = notes
    self.locationName = locationName
    self.observerEmail = observerEmail
    self.photoCount = photoCount
    self.clientSubmissionID = clientSubmissionID
    self.ecotypeGuess = ecotypeGuess
    self.localIdentification = localIdentification
  }
}

public struct SubmissionPayload: Codable, Hashable, Sendable {
  public let clientSubmissionID: UUID
  public let latitude: Double
  public let longitude: Double
  public let observedAt: Date
  public let groupSize: Int
  public let notes: String?
  public let locationName: String?
  public let observerEmail: String?
  public let photoCount: Int
  public let ecotypeGuess: Ecotype?
  public let localIdentification: LocalIdentificationSuggestion?
  public let existingReceipt: SubmissionReceipt?

  public init(
    clientSubmissionID: UUID = UUID(),
    latitude: Double,
    longitude: Double,
    observedAt: Date,
    groupSize: Int,
    notes: String?,
    locationName: String?,
    observerEmail: String?,
    photoCount: Int,
    ecotypeGuess: Ecotype? = nil,
    localIdentification: LocalIdentificationSuggestion? = nil,
    existingReceipt: SubmissionReceipt? = nil
  ) {
    self.clientSubmissionID = clientSubmissionID
    self.latitude = latitude
    self.longitude = longitude
    self.observedAt = observedAt
    self.groupSize = groupSize
    self.notes = notes
    self.locationName = locationName
    self.observerEmail = observerEmail
    self.photoCount = photoCount
    self.ecotypeGuess = ecotypeGuess
    self.localIdentification = localIdentification
    self.existingReceipt = existingReceipt
  }

  public func resuming(receipt: SubmissionReceipt) -> SubmissionPayload {
    SubmissionPayload(
      clientSubmissionID: clientSubmissionID,
      latitude: latitude,
      longitude: longitude,
      observedAt: observedAt,
      groupSize: groupSize,
      notes: notes,
      locationName: locationName,
      observerEmail: observerEmail,
      photoCount: photoCount,
      ecotypeGuess: ecotypeGuess,
      localIdentification: localIdentification,
      existingReceipt: receipt
    )
  }

  public func removingObserverEmail() -> SubmissionPayload {
    SubmissionPayload(
      clientSubmissionID: clientSubmissionID,
      latitude: latitude,
      longitude: longitude,
      observedAt: observedAt,
      groupSize: groupSize,
      notes: notes,
      locationName: locationName,
      observerEmail: nil,
      photoCount: photoCount,
      ecotypeGuess: ecotypeGuess,
      localIdentification: localIdentification,
      existingReceipt: existingReceipt
    )
  }

  enum CodingKeys: String, CodingKey {
    case clientSubmissionID = "client_submission_id"
    case latitude, longitude
    case observedAt = "observed_at"
    case groupSize = "group_size"
    case notes
    case locationName = "location_name"
    case observerEmail = "observer_email"
    case photoCount = "photo_count"
    case ecotypeGuess = "ecotype_guess"
    case localIdentification = "local_identification"
    case existingReceipt = "existing_receipt"
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    clientSubmissionID = try values.decode(UUID.self, forKey: .clientSubmissionID)
    latitude = try values.decode(Double.self, forKey: .latitude)
    longitude = try values.decode(Double.self, forKey: .longitude)
    observedAt = try values.decode(Date.self, forKey: .observedAt)
    groupSize = try values.decode(Int.self, forKey: .groupSize)
    notes = try values.decodeIfPresent(String.self, forKey: .notes)
    locationName = try values.decodeIfPresent(String.self, forKey: .locationName)
    observerEmail = try values.decodeIfPresent(String.self, forKey: .observerEmail)
    photoCount = try values.decode(Int.self, forKey: .photoCount)
    ecotypeGuess = try values.decodeIfPresent(Ecotype.self, forKey: .ecotypeGuess)
    localIdentification =
      (try? values.decodeIfPresent(
        LocalIdentificationSuggestion.self,
        forKey: .localIdentification
      )) ?? nil
    existingReceipt = try values.decodeIfPresent(SubmissionReceipt.self, forKey: .existingReceipt)
  }
}

public struct ProcessedPhoto: Codable, Hashable, Sendable {
  public let bytes: Data
  public let fileName: String
  public let mimeType: String
  public let idempotencyID: UUID

  public init(
    bytes: Data,
    fileName: String,
    mimeType: String = "image/jpeg",
    idempotencyID: UUID = UUID()
  ) {
    self.bytes = bytes
    self.fileName = fileName
    self.mimeType = mimeType
    self.idempotencyID = idempotencyID
  }
}

public struct SubmissionReceipt: Codable, Hashable, Sendable {
  public let id: String
  public let photoUploadToken: String

  public init(id: String, photoUploadToken: String) {
    self.id = id
    self.photoUploadToken = photoUploadToken
  }

  enum CodingKeys: String, CodingKey {
    case id
    case photoUploadToken
    case legacyPhotoUploadToken = "photo_upload_token"
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    if let token = try container.decodeIfPresent(String.self, forKey: .photoUploadToken) {
      photoUploadToken = token
    } else {
      photoUploadToken = try container.decode(String.self, forKey: .legacyPhotoUploadToken)
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(photoUploadToken, forKey: .photoUploadToken)
  }
}
