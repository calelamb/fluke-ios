import Foundation
import Observation
import FlukeKit

@MainActor
@Observable
public final class RangeViewModel {

    public private(set) var sightings: [HistoricalSighting] = []
    public var selectedPod: Pod = .j
    public var activeMonths: Set<Int> = Set(1...12)

    private let repository: HistoricalSightingsRepository

    public init(repository: HistoricalSightingsRepository) {
        self.repository = repository
    }

    public func load() async {
        do {
            let to = Date()
            let from = to.addingTimeInterval(-BrowseRequestValidator.maximumWindow)
            sightings = try await repository.fetch(from: from, to: to, pod: selectedPod, whaleId: nil)
        } catch {
            sightings = []
        }
    }

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
            let gx = Int(((sighting.longitude + 124.7) / 0.045).rounded(.down))
            let gy = Int(((49.5 - sighting.latitude) / 0.045).rounded(.down))
            bins["\(gx),\(gy)", default: 0] += 1
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
}
