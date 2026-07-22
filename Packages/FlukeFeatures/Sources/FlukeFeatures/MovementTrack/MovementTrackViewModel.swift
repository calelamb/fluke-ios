import CoreLocation
import FlukeKit
import Foundation
import Observation

@MainActor
@Observable
public final class MovementTrackViewModel {
  public enum Presentation: Equatable, Sendable {
    case loading
    case ready
    case sparse
    case empty
    case failed(BrowseFailure)
  }

  public static let secondsPerYear = 6.0
  public static let sparseMessage = "Not enough sightings yet to trace a movement pattern."

  public let whale: Whale
  public private(set) var state: BrowseViewState<[MovementTrackPoint]> = .idle
  public private(set) var selectedSeasons = Set(MovementSeason.allCases)
  public private(set) var scrubberDate: Date
  public private(set) var focusedPoint: MovementTrackPoint?
  public private(set) var isPlaying = false

  private let repository: any WhalesRepositoryProtocol
  private let now: () -> Date
  private var reduceMotionEnabled = false
  private var playbackElapsed = 0.0
  private var loadGeneration = 0

  public init(
    repository: any WhalesRepositoryProtocol,
    whale: Whale,
    now: @escaping () -> Date = Date.init
  ) {
    self.repository = repository
    self.whale = whale
    self.now = now
    scrubberDate = now()
  }

  public func load() async {
    loadGeneration += 1
    let generation = loadGeneration
    state = state.beginRefresh()
    let result: BrowseResult<[MovementTrackPoint]>
    do {
      let upperBound = now()
      result = try await repository.loadTrack(
        whaleId: whale.id,
        from: upperBound.addingTimeInterval(-BrowseRequestValidator.maximumWindow),
        to: upperBound
      )
    } catch {
      result = .failed(.unexpectedFeatureFailure)
    }
    guard generation == loadGeneration else { return }
    state = .resolve(Self.sorted(result))
    scrubberDate = points.last?.observedAt ?? now()
    focusedPoint = points.last
    isPlaying = false
    playbackElapsed = 0
  }

  public func retry() async { await load() }

  public var points: [MovementTrackPoint] { state.value ?? [] }
  public var stats: MovementTrackStats? { MovementTrackStats(points: points) }
  public var sparseMessage: String { Self.sparseMessage }
  public var browseNotice: BrowseNotice? { state.notice }

  public var presentation: Presentation {
    if state.isLoading, points.isEmpty { return .loading }
    if let failure = state.failure, points.isEmpty { return .failed(failure) }
    if points.isEmpty { return .empty }
    if points.count < 3 { return .sparse }
    return .ready
  }

  public var dateRange: ClosedRange<Date>? {
    guard let first = points.first?.observedAt, let last = points.last?.observedAt else {
      return nil
    }
    return first...last
  }

  public var visiblePoints: [SeasonalMovementPoint] {
    points.compactMap { point in
      let season = MovementSeason.season(for: point.observedAt)
      guard selectedSeasons.contains(season), point.observedAt <= scrubberDate else { return nil }
      return SeasonalMovementPoint(point: point, season: season)
    }
  }

  public var visiblePolyline: [MovementTrackPoint] {
    let filtered = visiblePoints.map(\.point)
    guard filtered.count >= 3 else { return [] }
    return filtered
  }

  public var accessibilitySummary: String {
    guard let stats else { return "No movement sightings are available." }
    let distance = Measurement(value: stats.northSouthDistanceMeters, unit: UnitLength.meters)
      .converted(to: .kilometers)
      .value
      .formatted(.number.precision(.fractionLength(0)))
    let first = stats.firstSeen.formatted(.dateTime.month(.wide).year())
    let last = stats.lastSeen.formatted(.dateTime.month(.wide).year())
    return
      "\(stats.sightingCount) sightings from \(first) to \(last), spanning \(distance) kilometers north to south."
  }

  public var focusedPointAccessibilityLabel: String {
    guard let focusedPoint else { return "No focused sighting." }
    let location = focusedPoint.locationName ?? "Salish Sea"
    let date = focusedPoint.observedAt.formatted(date: .complete, time: .omitted)
    let notes = focusedPoint.behaviorNotes.flatMap(Self.normalized)
    return ["Focused sighting", location, date, notes].compactMap { $0 }.joined(separator: ", ")
  }

  public func setSeasons(_ seasons: Set<MovementSeason>) {
    selectedSeasons = seasons
    if let focusedPoint, !visiblePoints.contains(where: { $0.id == focusedPoint.id }) {
      self.focusedPoint = visiblePoints.last?.point
    }
  }

  public func toggleSeason(_ season: MovementSeason) {
    let updated =
      selectedSeasons.contains(season)
      ? selectedSeasons.subtracting([season])
      : selectedSeasons.union([season])
    setSeasons(updated)
  }

  public func setScrubberDate(_ date: Date) {
    guard let range = dateRange else { return }
    scrubberDate = min(max(date, range.lowerBound), range.upperBound)
    playbackElapsed = Self.playbackElapsed(
      from: range.lowerBound,
      to: scrubberDate,
      secondsPerYear: Self.secondsPerYear
    )
    focusedPoint = visiblePoints.last?.point
    if scrubberDate == range.upperBound { isPlaying = false }
  }

  public func focus(nearestToLatitude latitude: Double, longitude: Double) {
    let target = CLLocation(latitude: latitude, longitude: longitude)
    focusedPoint =
      visiblePoints.min { left, right in
        Self.distance(from: left.point, to: target) < Self.distance(from: right.point, to: target)
      }?.point
  }

  public func restartPlayback() {
    guard !reduceMotionEnabled, presentation == .ready, let first = dateRange?.lowerBound else {
      return
    }
    playbackElapsed = 0
    scrubberDate = first
    focusedPoint = visiblePoints.last?.point
    isPlaying = true
  }

  public func togglePlayback() {
    guard !reduceMotionEnabled else { return }
    if isPlaying {
      isPlaying = false
    } else if scrubberDate == dateRange?.upperBound {
      restartPlayback()
    } else {
      isPlaying = presentation == .ready
    }
  }

  public func advancePlayback(by elapsed: TimeInterval) {
    guard isPlaying, elapsed > 0, let range = dateRange else { return }
    playbackElapsed += elapsed
    let date = Self.playbackDate(
      from: range.lowerBound,
      elapsed: playbackElapsed,
      secondsPerYear: Self.secondsPerYear
    )
    setScrubberDate(min(date, range.upperBound))
  }

  public func setReduceMotion(_ reduceMotion: Bool) {
    reduceMotionEnabled = reduceMotion
    guard reduceMotion, let finalDate = dateRange?.upperBound else { return }
    scrubberDate = finalDate
    focusedPoint = visiblePoints.last?.point
    isPlaying = false
  }

  private static func distance(from point: MovementTrackPoint, to location: CLLocation)
    -> CLLocationDistance
  {
    CLLocation(latitude: point.latitude, longitude: point.longitude).distance(from: location)
  }

  private static func normalized(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func playbackDate(
    from start: Date,
    elapsed: TimeInterval,
    secondsPerYear: TimeInterval
  ) -> Date {
    let calendar = Calendar(identifier: .gregorian)
    let years = elapsed / secondsPerYear
    let wholeYears = Int(years.rounded(.down))
    let fraction = years - Double(wholeYears)
    let lower = calendar.date(byAdding: .year, value: wholeYears, to: start) ?? start
    guard fraction > 0,
      let upper = calendar.date(byAdding: .year, value: 1, to: lower)
    else { return lower }
    return lower.addingTimeInterval(upper.timeIntervalSince(lower) * fraction)
  }

  private static func playbackElapsed(
    from start: Date,
    to date: Date,
    secondsPerYear: TimeInterval
  ) -> TimeInterval {
    guard date > start else { return 0 }
    let calendar = Calendar(identifier: .gregorian)
    let wholeYears = max(calendar.dateComponents([.year], from: start, to: date).year ?? 0, 0)
    let lower = calendar.date(byAdding: .year, value: wholeYears, to: start) ?? start
    guard let upper = calendar.date(byAdding: .year, value: 1, to: lower) else {
      return Double(wholeYears) * secondsPerYear
    }
    let yearDuration = upper.timeIntervalSince(lower)
    let fraction = min(max(date.timeIntervalSince(lower) / yearDuration, 0), 1)
    return (Double(wholeYears) + fraction) * secondsPerYear
  }

  private static func sorted(
    _ result: BrowseResult<[MovementTrackPoint]>
  ) -> BrowseResult<[MovementTrackPoint]> {
    func sort(_ points: [MovementTrackPoint]) -> [MovementTrackPoint] {
      points.sorted {
        if $0.observedAt == $1.observedAt { return $0.id < $1.id }
        return $0.observedAt < $1.observedAt
      }
    }
    return switch result {
    case .cached(let payload, let metadata):
      .cached(payload: map(payload, sort), metadata: metadata)
    case .fresh(let points, let metadata): .fresh(value: sort(points), metadata: metadata)
    case .empty(let metadata): .empty(metadata: metadata)
    case .stale(let payload, let metadata, let failure):
      .stale(payload: map(payload, sort), metadata: metadata, failure: failure)
    case .cachedOffline(let payload, let metadata):
      .cachedOffline(payload: map(payload, sort), metadata: metadata)
    case .failed(let failure): .failed(failure)
    }
  }

  private static func map(
    _ payload: BrowsePayload<[MovementTrackPoint]>,
    _ transform: ([MovementTrackPoint]) -> [MovementTrackPoint]
  ) -> BrowsePayload<[MovementTrackPoint]> {
    switch payload {
    case .value(let points): .value(transform(points))
    case .empty: .empty
    }
  }
}
