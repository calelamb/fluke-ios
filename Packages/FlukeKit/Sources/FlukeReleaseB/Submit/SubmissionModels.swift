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

  public init(
    latitude: Double,
    longitude: Double,
    observedAt: Date,
    groupSize: Int,
    notes: String? = nil,
    locationName: String? = nil,
    observerEmail: String? = nil,
    photoCount: Int
  ) {
    self.latitude = latitude
    self.longitude = longitude
    self.observedAt = observedAt
    self.groupSize = groupSize
    self.notes = notes
    self.locationName = locationName
    self.observerEmail = observerEmail
    self.photoCount = photoCount
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
    case existingReceipt = "existing_receipt"
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
    case photoUploadToken = "photo_upload_token"
  }
}
