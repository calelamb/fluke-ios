import Foundation
import Observation
import FlukeKit

@MainActor
@Observable
public final class TraceViewModel {

    public enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case sparse(reason: String)
        case error(String)
    }

    public private(set) var loadState: LoadState = .idle
    public private(set) var points: [MovementTrackPoint] = []
    public var selectedWhaleId: String? {
        didSet { Task { await loadIfNeeded() } }
    }
    public var scrubberDate: Date = Date()

    private let whales: WhalesRepository

    public init(repository: WhalesRepository) {
        self.whales = repository
    }

    public func loadIfNeeded() async {
        guard let id = selectedWhaleId else {
            loadState = .idle
            points = []
            return
        }
        loadState = .loading
        do {
            let fetched = try await whales.fetchTrack(whaleId: id)
            points = fetched.sorted { $0.observedAt < $1.observedAt }
            if points.count < 3 {
                loadState = .sparse(reason: "Not enough sightings yet to trace movement.")
            } else {
                loadState = .loaded
                if let last = points.last { scrubberDate = last.observedAt }
            }
        } catch {
            loadState = .error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    public var dateRange: ClosedRange<Date>? {
        guard let first = points.first?.observedAt, let last = points.last?.observedAt else { return nil }
        return first...last
    }

    public var visiblePoints: [MovementTrackPoint] {
        points.filter { $0.observedAt <= scrubberDate }
    }
}
