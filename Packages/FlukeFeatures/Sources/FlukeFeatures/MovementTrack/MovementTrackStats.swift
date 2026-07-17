import CoreLocation
import FlukeKit
import Foundation

public struct MovementTrackStats: Equatable, Sendable {
  public let sightingCount: Int
  public let northSouthDistanceMeters: CLLocationDistance
  public let firstSeen: Date
  public let lastSeen: Date

  public init?(points: [MovementTrackPoint]) {
    guard
      let first = points.min(by: { $0.observedAt < $1.observedAt }),
      let last = points.max(by: { $0.observedAt < $1.observedAt }),
      let northernmost = points.max(by: { $0.latitude < $1.latitude }),
      let southernmost = points.min(by: { $0.latitude < $1.latitude })
    else { return nil }

    sightingCount = points.count
    northSouthDistanceMeters = CLLocation(
      latitude: northernmost.latitude,
      longitude: northernmost.longitude
    ).distance(
      from: CLLocation(
        latitude: southernmost.latitude,
        longitude: southernmost.longitude
      ))
    firstSeen = first.observedAt
    lastSeen = last.observedAt
  }
}

public enum MovementSeason: String, CaseIterable, Identifiable, Sendable {
  case winter = "Winter"
  case spring = "Spring"
  case summer = "Summer"
  case fall = "Fall"

  public var id: String { rawValue }

  public static func season(
    for date: Date,
    calendar: Calendar = Calendar(identifier: .gregorian)
  ) -> MovementSeason {
    switch calendar.component(.month, from: date) {
    case 3...5: .spring
    case 6...8: .summer
    case 9...11: .fall
    default: .winter
    }
  }
}

public struct SeasonalMovementPoint: Identifiable, Equatable, Sendable {
  public let point: MovementTrackPoint
  public let season: MovementSeason

  public var id: String { point.id }
  public var observedAt: Date { point.observedAt }
}
