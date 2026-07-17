import Foundation
import Observation
import FlukeKit

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
        if activeMonths.contains(month) { activeMonths.remove(month) } else { activeMonths.insert(month) }
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

    private func invalidateQueryState() {
        loadGeneration += 1
        state = .idle
    }
}
