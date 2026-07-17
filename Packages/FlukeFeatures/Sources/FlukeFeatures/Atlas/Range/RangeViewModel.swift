import FlukeKit
import Foundation
import Observation

enum RangeGridProjection {
  static let cellDegrees = 0.045
  static let projection = SalishSeaProjection.salishSea
  static let columnCount = cellCount(for: projection.east - projection.west)
  static let rowCount = cellCount(for: projection.north - projection.south)

  static func bin(latitude: Double, longitude: Double) -> (x: Int, y: Int) {
    let rawX = Int(floor((longitude - projection.west) / cellDegrees))
    let rawY = Int(floor((projection.north - latitude) / cellDegrees))
    return (
      x: min(max(rawX, 0), columnCount - 1),
      y: min(max(rawY, 0), rowCount - 1)
    )
  }

  static func normalizedCenter(x: Int, y: Int) -> (x: Double, y: Double) {
    let west = projection.west + Double(x) * cellDegrees
    let east = min(west + cellDegrees, projection.east)
    let north = projection.north - Double(y) * cellDegrees
    let south = max(north - cellDegrees, projection.south)
    let longitude = (west + east) / 2
    let latitude = (north + south) / 2
    return projection.project(lat: latitude, lng: longitude)
  }

  private static func cellCount(for span: Double) -> Int {
    Int(ceil(span / cellDegrees - 1e-9))
  }
}

public enum RangeHeatmapPresentation {
  public static func intensity(count: Int, maximum: Int) -> Double {
    guard count > 0, maximum > 0 else { return 0 }
    return min(max(Double(count) / Double(maximum), 0), 1)
  }
}

@MainActor
@Observable
public final class RangeViewModel {
  public private(set) var state: BrowseViewState<[HistoricalSighting]> = .idle
  public var selectedPod: Pod = .j {
    didSet {
      guard selectedPod != oldValue else { return }
      invalidateQueryState()
    }
  }
  public var activeMonths: Set<Int> = Set(1...12)

  private let repository: any HistoricalSightingsRepositoryProtocol
  private let now: () -> Date
  private var loadGeneration = 0

  public init(
    repository: any HistoricalSightingsRepositoryProtocol,
    now: @escaping () -> Date = Date.init
  ) {
    self.repository = repository
    self.now = now
  }

  init(
    repository: any HistoricalSightingsRepositoryProtocol,
    now: @escaping () -> Date = Date.init,
    initialState: BrowseViewState<[HistoricalSighting]>
  ) {
    self.repository = repository
    self.now = now
    state = initialState
  }

  public func load() async {
    loadGeneration += 1
    let generation = loadGeneration
    state = state.beginRefresh()
    let result: BrowseResult<[HistoricalSighting]>
    do {
      let to = now()
      let from = to.addingTimeInterval(-BrowseRequestValidator.maximumWindow)
      result = try await repository.load(from: from, to: to, pod: selectedPod)
    } catch {
      result = .failed(.unexpectedFeatureFailure)
    }
    guard generation == loadGeneration else { return }
    state = .resolve(result)
  }

  public func retry() async { await load() }

  public var sightings: [HistoricalSighting] { state.value ?? [] }

  public func toggleMonth(_ month: Int) {
    if activeMonths.contains(month) {
      activeMonths.remove(month)
    } else {
      activeMonths.insert(month)
    }
  }

  /// Aggregate sightings into 5km grid cells (~0.045° per cell), filtered to active months.
  /// Returns array of (gridX, gridY, count).
  public var heatmap: [(x: Int, y: Int, count: Int)] {
    var bins: [String: Int] = [:]
    let cal = Calendar(identifier: .gregorian)
    for sighting in sightings {
      let month = cal.component(.month, from: sighting.observedAt)
      guard activeMonths.contains(month) else { continue }
      let cell = RangeGridProjection.bin(
        latitude: sighting.latitude,
        longitude: sighting.longitude
      )
      bins["\(cell.x),\(cell.y)", default: 0] += 1
    }
    return bins.compactMap { (k, v) in
      let parts = k.split(separator: ",").compactMap { Int($0) }
      guard parts.count == 2 else { return nil }
      return (x: parts[0], y: parts[1], count: v)
    }
  }

  public var maxCount: Int {
    heatmap.map { $0.count }.max() ?? 1
  }

  public var accessibilitySummary: String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    let months = activeMonths.sorted().compactMap { month -> String? in
      guard (1...12).contains(month) else { return nil }
      return formatter.monthSymbols[month - 1]
    }
    let monthSummary: String
    if months.count == 12 {
      monthSummary = "all months"
    } else if months.isEmpty {
      monthSummary = "no months"
    } else {
      monthSummary = months.joined(separator: ", ")
    }
    let total = heatmap.reduce(0) { $0 + $1.count }
    let noun = total == 1 ? "sighting" : "sightings"
    return
      "Historical range for \(selectedPod.displayName), \(monthSummary): \(total) \(noun) in \(heatmap.count) map cells."
  }

  public var statusComposition: AtlasStatusComposition {
    AtlasStatusComposition(
      notice: state.notice,
      truth: hasConfirmedEmpty
        ? .empty("No range data for this pod and window.")
        : nil
    )
  }

  private var hasConfirmedEmpty: Bool {
    switch state {
    case .empty: true
    case .content(let sightings, _, _): sightings.isEmpty
    case .idle, .loading, .failed: false
    }
  }

  private func invalidateQueryState() {
    loadGeneration += 1
    state = .idle
  }
}
