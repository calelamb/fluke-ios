import FlukeKit
import Foundation

public enum LogbookStatus: String, CaseIterable, Codable, Hashable, Sendable {
  case queued
  case pending
  case approved
  case rejected
}

public struct LogbookEntry: Codable, Hashable, Identifiable, Sendable {
  public let id: String
  public let observedAt: Date
  public let locationName: String?
  public let status: LogbookStatus
  public let createdAt: Date?
  public let photoCount: Int
  public let rejectionReason: String?

  public init(
    id: String,
    observedAt: Date,
    locationName: String?,
    status: LogbookStatus,
    createdAt: Date? = nil,
    photoCount: Int = 0,
    rejectionReason: String? = nil
  ) {
    self.id = id
    self.observedAt = observedAt
    self.locationName = locationName
    self.status = status
    self.createdAt = createdAt
    self.photoCount = photoCount
    self.rejectionReason = rejectionReason
  }
}
