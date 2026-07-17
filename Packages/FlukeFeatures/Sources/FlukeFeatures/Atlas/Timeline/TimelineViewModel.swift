import Foundation
import Observation
import SwiftUI
import FlukeKit

@MainActor
@Observable
public final class TimelineViewModel {
    public private(set) var state: BrowseViewState<[HistoricalSighting]> = .idle
    public var scrubberDate: Date = Date()
    public var activePods: Set<Pod> = Set(Pod.allCases)

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
            result = try await repository.load(from: from, to: to, pod: nil)
        } catch {
            result = .failed(.unexpectedFeatureFailure)
        }
        guard generation == loadGeneration else { return }
        state = .resolve(result)
        if let last = historicalSightings.max(by: { $0.observedAt < $1.observedAt }) {
            scrubberDate = last.observedAt
        }
    }

    public func retry() async { await load() }

    public var historicalSightings: [HistoricalSighting] { state.value ?? [] }

    public func togglePod(_ pod: Pod) {
        if activePods.contains(pod) { activePods.remove(pod) } else { activePods.insert(pod) }
    }

    public var dateRange: ClosedRange<Date>? {
        let dates = historicalSightings.map(\.observedAt)
        guard let first = dates.min(), let last = dates.max() else { return nil }
        return first...last
    }

    /// Returns sightings on or before scrubberDate, grouped by pod via whale lookup.
    public func tracks(catalog: [Whale]) -> [Pod: [(lat: Double, lng: Double, observedAt: Date)]] {
        let upTo = historicalSightings.filter { $0.observedAt <= scrubberDate }
        var byPod: [Pod: [(lat: Double, lng: Double, observedAt: Date)]] = [:]

        let podByWhale = catalog.reduce(into: [String: Pod]()) { result, whale in
            guard let pod = pod(for: whale) else { return }
            result[whale.id] = pod
            result[whale.catalogId] = pod
        }

        for sighting in upTo {
            let sightingPods = Set(sighting.whaleIds.compactMap { podByWhale[$0] })
            for pod in sightingPods where activePods.contains(pod) {
                byPod[pod, default: []].append((sighting.latitude, sighting.longitude, sighting.observedAt))
            }
        }

        for pod in byPod.keys {
            byPod[pod]?.sort { $0.observedAt < $1.observedAt }
        }

        return byPod
    }

    private func pod(for whale: Whale) -> Pod? {
        switch whale.pod {
        case "J": .j
        case "K": .k
        case "L": .l
        default: whale.ecotype == .biggs ? .biggs : nil
        }
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
