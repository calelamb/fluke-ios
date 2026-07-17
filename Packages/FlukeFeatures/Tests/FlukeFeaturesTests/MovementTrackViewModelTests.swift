import CoreLocation
import FlukeFeatures
import FlukeKit
import Foundation
import Testing

@MainActor
@Suite("Whale movement presentation")
struct MovementTrackViewModelTests {
  @Test("A track needs three points before drawing a pattern")
  func sparseTrack() async {
    let model = MovementTrackViewModel(
      repository: MovementTrackRepository(points: [.january, .june]),
      whale: .movementFixture,
      now: { .october }
    )

    await model.load()

    #expect(model.presentation == .sparse)
    #expect(model.visiblePolyline.isEmpty)
    #expect(model.sparseMessage == "Not enough sightings yet to trace a movement pattern.")
  }

  @Test("Season and scrubber filters compose")
  func combinedFilters() async {
    let model = MovementTrackViewModel(
      repository: MovementTrackRepository(points: MovementTrackPoint.yearFixture),
      whale: .movementFixture,
      now: { .november }
    )
    await model.load()

    model.setSeasons([.summer, .fall])
    model.setScrubberDate(.october)

    #expect(!model.visiblePoints.isEmpty)
    #expect(
      model.visiblePoints.allSatisfy {
        Set([MovementSeason.summer, .fall]).contains($0.season)
          && $0.observedAt <= Date.october
      })
  }

  @Test("Range measures northernmost to southernmost observations")
  func northSouthRange() async throws {
    let model = loadedModel(points: MovementTrackPoint.yearFixture)
    await model.load()

    let stats = try #require(model.stats)
    let north = CLLocation(latitude: 49.2, longitude: -123.4)
    let south = CLLocation(latitude: 47.4, longitude: -122.5)

    #expect(abs(stats.northSouthDistanceMeters - north.distance(from: south)) < 0.5)
    #expect(stats.firstSeen == .january)
    #expect(stats.lastSeen == .november)
  }

  @Test("Map focus selects the nearest visible observation")
  func nearestFocusPoint() async {
    let model = loadedModel(points: MovementTrackPoint.yearFixture)
    await model.load()

    model.focus(nearestToLatitude: 48.61, longitude: -123.21)

    #expect(model.focusedPoint?.id == MovementTrackPoint.june.id)
  }

  @Test("Playback reveals one calendar year every six seconds")
  func playbackRate() async {
    let model = loadedModel(points: [.january, .nextJanuary, .nextNovember])
    await model.load()
    model.restartPlayback()

    model.advancePlayback(by: 3)
    let halfway = model.scrubberDate
    model.advancePlayback(by: 3)

    #expect(halfway > Date.january)
    #expect(halfway < Date.nextJanuary)
    #expect(abs(model.scrubberDate.timeIntervalSince(Date.nextJanuary)) < 1)
    #expect(model.isPlaying)
  }

  @Test("Playback pauses at the final observation")
  func playbackPausesAtEnd() async {
    let model = loadedModel(points: [.january, .nextJanuary])
    await model.load()
    model.restartPlayback()

    model.advancePlayback(by: 60)

    #expect(model.scrubberDate == .nextJanuary)
    #expect(!model.isPlaying)
  }

  @Test("Playback resumes from a manually scrubbed date")
  func playbackResumesFromScrubber() async {
    let model = loadedModel(points: [.january, .nextJanuary, .nextNovember])
    await model.load()
    model.setScrubberDate(.october)

    model.togglePlayback()
    model.advancePlayback(by: 0.1)

    #expect(model.scrubberDate > .october)
  }

  @Test("Reduce Motion reveals the full track without playback")
  func reduceMotionReveal() async {
    let model = loadedModel(points: MovementTrackPoint.yearFixture)
    await model.load()
    model.restartPlayback()

    model.setReduceMotion(true)

    #expect(model.scrubberDate == .november)
    #expect(model.visiblePoints.count == MovementTrackPoint.yearFixture.count)
    #expect(!model.isPlaying)
  }

  @Test("Reduce Motion keeps playback paused")
  func reduceMotionKeepsPlaybackPaused() async {
    let model = loadedModel(points: MovementTrackPoint.yearFixture)
    await model.load()
    model.setReduceMotion(true)

    model.togglePlayback()

    #expect(model.scrubberDate == .november)
    #expect(!model.isPlaying)
  }

  @Test("Movement controls and summary are accessible")
  func accessibilityContracts() async {
    let model = loadedModel(points: MovementTrackPoint.yearFixture)
    await model.load()

    #expect(MovementTrackView.minimumControlSize == 44)
    #expect(model.accessibilitySummary.contains("4 sightings"))
    #expect(model.accessibilitySummary.contains("January 2024"))
    #expect(model.accessibilitySummary.contains("November 2024"))
  }

  private func loadedModel(points: [MovementTrackPoint]) -> MovementTrackViewModel {
    MovementTrackViewModel(
      repository: MovementTrackRepository(points: points),
      whale: .movementFixture,
      now: { .nextNovember }
    )
  }
}

private struct MovementTrackRepository: WhalesRepositoryProtocol {
  let points: [MovementTrackPoint]

  func loadCatalog() async throws -> BrowseResult<[Whale]> { .empty(metadata: .fixture) }
  func loadProfile(id: String) async throws -> BrowseResult<WhaleProfile?> {
    .empty(metadata: .fixture)
  }
  func loadTrack(
    whaleId: String,
    from: Date,
    to: Date
  ) async throws -> BrowseResult<[MovementTrackPoint]> {
    .fresh(value: points, metadata: .fixture)
  }
}

extension BrowseMetadata {
  fileprivate static let fixture = BrowseMetadata(fetchedAt: .january, schemaVersion: 1)
}

extension Whale {
  fileprivate static let movementFixture = Whale(
    id: "whale-j35",
    catalogId: "J35",
    name: "Tahlequah",
    ecotype: .resident,
    pod: "J",
    sex: .female,
    birthYear: 1998,
    deathYear: nil,
    status: .alive,
    biography: nil,
    distinguishingMarks: nil,
    heroImageUrl: nil,
    notableEvents: [],
    sourceCitations: []
  )
}

extension Date {
  fileprivate static let january = makeUTCDate(2024, 1, 1)
  fileprivate static let june = makeUTCDate(2024, 6, 1)
  fileprivate static let october = makeUTCDate(2024, 10, 1)
  fileprivate static let november = makeUTCDate(2024, 11, 1)
  fileprivate static let nextJanuary = makeUTCDate(2025, 1, 1)
  fileprivate static let nextNovember = makeUTCDate(2025, 11, 1)

  fileprivate static func makeUTCDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
  }
}

extension MovementTrackPoint {
  fileprivate static let january = MovementTrackPoint(
    id: "jan",
    observedAt: .january,
    latitude: 49.2,
    longitude: -123.4,
    locationName: "Strait of Georgia",
    behaviorNotes: "Traveling"
  )
  fileprivate static let june = MovementTrackPoint(
    id: "jun",
    observedAt: .june,
    latitude: 48.6,
    longitude: -123.2,
    locationName: "Haro Strait",
    behaviorNotes: "Foraging"
  )
  fileprivate static let october = MovementTrackPoint(
    id: "oct",
    observedAt: .october,
    latitude: 48.0,
    longitude: -122.8,
    locationName: "Admiralty Inlet",
    behaviorNotes: nil
  )
  fileprivate static let november = MovementTrackPoint(
    id: "nov",
    observedAt: .november,
    latitude: 47.4,
    longitude: -122.5,
    locationName: "Puget Sound",
    behaviorNotes: nil
  )
  fileprivate static let nextJanuary = MovementTrackPoint(
    id: "next-jan",
    observedAt: .nextJanuary,
    latitude: 48.1,
    longitude: -122.9,
    locationName: "Admiralty Inlet",
    behaviorNotes: nil
  )
  fileprivate static let nextNovember = MovementTrackPoint(
    id: "next-nov",
    observedAt: .nextNovember,
    latitude: 47.8,
    longitude: -122.7,
    locationName: "Puget Sound",
    behaviorNotes: nil
  )

  fileprivate static let yearFixture = [january, june, october, november]
}
