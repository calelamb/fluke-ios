import Foundation
import Observation
import SwiftUI
import FlukeKit

@MainActor
@Observable
public final class TimelineViewModel {

    public enum LoadState: Equatable { case loading, loaded, error(String) }

    public private(set) var loadState: LoadState = .loading
    public private(set) var historicalSightings: [HistoricalSighting] = []
    public var scrubberDate: Date = Date()
    public var activePods: Set<Pod> = Set(Pod.allCases)

    private let repository: HistoricalSightingsRepository

    public init(repository: HistoricalSightingsRepository) {
        self.repository = repository
    }

    public func load() async {
        loadState = .loading
        do {
            let to = Date()
            let from = to.addingTimeInterval(-BrowseRequestValidator.maximumWindow)
            historicalSightings = try await repository.fetch(from: from, to: to, pod: nil, whaleId: nil)
            loadState = .loaded
            if let last = historicalSightings.last?.observedAt { scrubberDate = last }
        } catch {
            loadState = .error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    public func togglePod(_ pod: Pod) {
        if activePods.contains(pod) { activePods.remove(pod) } else { activePods.insert(pod) }
    }

    public var dateRange: ClosedRange<Date>? {
        guard let first = historicalSightings.first?.observedAt,
              let last = historicalSightings.last?.observedAt else { return nil }
        return first...last
    }

    /// Returns sightings on or before scrubberDate, grouped by pod via whale lookup.
    public func tracks(catalog: [Whale]) -> [Pod: [(lat: Double, lng: Double, observedAt: Date)]] {
        let upTo = historicalSightings.filter { $0.observedAt <= scrubberDate }
        var byPod: [Pod: [(lat: Double, lng: Double, observedAt: Date)]] = [:]

        let podByWhale = Dictionary(uniqueKeysWithValues: catalog.compactMap { w -> (String, Pod)? in
            switch w.pod {
            case "J": return (w.id, .j)
            case "K": return (w.id, .k)
            case "L": return (w.id, .l)
            default:
                if w.ecotype == .biggs { return (w.id, .biggs) }
                return nil
            }
        })

        for sighting in upTo {
            for whaleId in sighting.whaleIds {
                guard let pod = podByWhale[whaleId], activePods.contains(pod) else { continue }
                byPod[pod, default: []].append((sighting.latitude, sighting.longitude, sighting.observedAt))
            }
        }

        for pod in byPod.keys {
            byPod[pod]?.sort { $0.observedAt < $1.observedAt }
        }

        return byPod
    }
}

public enum AtlasPodColor {
    public static func color(for pod: Pod) -> Color {
        switch pod {
        case .j: return .tide
        case .k: return .deep
        case .l: return .swell
        case .biggs: return .ember
        }
    }
}
