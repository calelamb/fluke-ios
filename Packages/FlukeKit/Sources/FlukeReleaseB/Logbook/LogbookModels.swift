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

  public init(
    id: String,
    observedAt: Date,
    locationName: String?,
    status: LogbookStatus
  ) {
    self.id = id
    self.observedAt = observedAt
    self.locationName = locationName
    self.status = status
  }

  init(sighting: Sighting) {
    id = sighting.id
    observedAt = sighting.observedAt
    locationName = sighting.locationName
    status =
      switch sighting.status {
      case .pending: .pending
      case .approved: .approved
      case .rejected: .rejected
      }
  }
}
