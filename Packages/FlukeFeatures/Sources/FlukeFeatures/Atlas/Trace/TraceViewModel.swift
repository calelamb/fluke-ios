import FlukeKit
import Foundation
import Observation

@MainActor
@Observable
public final class TraceViewModel {
  public private(set) var state: BrowseViewState<[MovementTrackPoint]> = .idle
  public var selectedWhaleId: String? {
    didSet {
      guard selectedWhaleId != oldValue else { return }
      invalidateQueryState()
    }
  }
  public var scrubberDate: Date = Date()

  private let whales: any WhalesRepositoryProtocol
  private let now: () -> Date
  private var loadGeneration = 0

  public init(
    repository: any WhalesRepositoryProtocol,
    selectedWhaleID: String? = nil,
    now: @escaping () -> Date = Date.init
  ) {
    self.whales = repository
    self.selectedWhaleId = selectedWhaleID
    self.now = now
  }

  public func loadIfNeeded() async {
    guard let id = selectedWhaleId else {
      state = .idle
      return
    }
    loadGeneration += 1
    let generation = loadGeneration
    state = state.beginRefresh()
    let result: BrowseResult<[MovementTrackPoint]>
    do {
      let to = now()
      let from = to.addingTimeInterval(-BrowseRequestValidator.maximumWindow)
      result = try await whales.loadTrack(whaleId: id, from: from, to: to)
    } catch {
      result = .failed(.unexpectedFeatureFailure)
    }
    guard generation == loadGeneration else { return }
    state = .resolve(Self.sorted(result))
    if let last = points.last { scrubberDate = last.observedAt }
  }

  public func retry() async { await loadIfNeeded() }

  public var points: [MovementTrackPoint] { state.value ?? [] }

  public var isSparse: Bool { !points.isEmpty && points.count < 3 }

  public var dateRange: ClosedRange<Date>? {
    guard let first = points.first?.observedAt, let last = points.last?.observedAt else {
      return nil
    }
    return first...last
  }

  public var visiblePoints: [MovementTrackPoint] {
    points.filter { $0.observedAt <= scrubberDate }
  }

  public func accessibilitySummary(catalog: [Whale]) -> String {
    let whale = catalog.first { $0.id == selectedWhaleId || $0.catalogId == selectedWhaleId }
    let subject = whale?.catalogId ?? "selected whale"
    let count = visiblePoints.count
    let noun = count == 1 ? "sighting" : "sightings"
    if isSparse {
      return
        "Trace for \(subject): \(count) \(noun). Not enough sightings to infer a movement pattern."
    }
    return
      "Historical trace for \(subject) through \(scrubberDate.formatted(date: .abbreviated, time: .omitted)): \(count) \(noun)."
  }

  private static func sorted(
    _ result: BrowseResult<[MovementTrackPoint]>
  ) -> BrowseResult<[MovementTrackPoint]> {
    func values(_ points: [MovementTrackPoint]) -> [MovementTrackPoint] {
      points.sorted { $0.observedAt < $1.observedAt }
    }
    return switch result {
    case .fresh(let points, let metadata):
      .fresh(value: values(points), metadata: metadata)
    case .empty(let metadata):
      .empty(metadata: metadata)
    case .stale(let payload, let metadata, let failure):
      .stale(payload: map(payload, transform: values), metadata: metadata, failure: failure)
    case .cachedOffline(let payload, let metadata):
      .cachedOffline(payload: map(payload, transform: values), metadata: metadata)
    case .failed(let failure):
      .failed(failure)
    }
  }

  private static func map(
    _ payload: BrowsePayload<[MovementTrackPoint]>,
    transform: ([MovementTrackPoint]) -> [MovementTrackPoint]
  ) -> BrowsePayload<[MovementTrackPoint]> {
    switch payload {
    case .value(let points): .value(transform(points))
    case .empty: .empty
    }
  }

  private func invalidateQueryState() {
    loadGeneration += 1
    state = .idle
  }
}
