import FlukeKit
import Foundation
import Observation

@MainActor
@Observable
public final class SightingsViewModel {
    public enum Mode: String, CaseIterable, Identifiable {
        case list = "List"
        case map = "Map"

        public var id: String { rawValue }
    }

    public struct DisplayItem: Hashable, Identifiable, Sendable {
        public enum Payload: Hashable, Sendable {
            case fluke(Sighting)
            case external(ExternalSighting)
        }

        public let id: String
        public let observedAt: Date
        public let latitude: Double
        public let longitude: Double
        public let locationName: String?
        public let ecotype: Ecotype?
        public let groupSize: Int?
        public let whaleCatalogIDs: [String]
        public let notes: String?
        public let sourceLabel: String
        public let payload: Payload

        public var locationLabel: String {
            let normalized = locationName?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let normalized, !normalized.isEmpty {
                return normalized
            }
            return "Salish Sea"
        }

        public var accessibilityLabel: String {
            let date = observedAt.formatted(date: .abbreviated, time: .shortened)
            let group = groupSize.map { ", group of \($0)" } ?? ""
            let type = ecotype.map { ", \($0.flukeDisplayName)" } ?? ""
            let whales = whaleCatalogIDs.isEmpty
                ? ""
                : ", whales \(whaleCatalogIDs.joined(separator: ", "))"
            return "\(locationLabel), \(date), \(sourceLabel)\(group)\(type)\(whales)"
        }
    }

    public private(set) var approvedState: BrowseViewState<[Sighting]> = .idle
    public private(set) var externalState: BrowseViewState<[ExternalSighting]> = .idle
    public var mode: Mode = .list
    public var selectedItem: DisplayItem?

    private let repository: any SightingsRepositoryProtocol
    private var loadGeneration = 0

    public init(repository: any SightingsRepositoryProtocol) {
        self.repository = repository
    }

    public func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        approvedState = approvedState.beginRefresh()
        externalState = externalState.beginRefresh()

        async let approved = Self.loadApproved(from: repository)
        async let external = Self.loadExternal(from: repository)
        let results = await (approved, external)
        guard generation == loadGeneration else { return }
        approvedState = .resolve(results.0)
        externalState = .resolve(results.1)
    }

    public func retry() async {
        await load()
    }

    public var items: [DisplayItem] {
        let approved = (approvedState.value ?? []).map { sighting in
            DisplayItem(
                id: "fluke:\(sighting.id)",
                observedAt: sighting.observedAt,
                latitude: sighting.latitude,
                longitude: sighting.longitude,
                locationName: sighting.locationName,
                ecotype: sighting.ecotypeGuess,
                groupSize: sighting.groupSize,
                whaleCatalogIDs: sighting.identifiedWhales.map(\.catalogId),
                notes: sighting.behaviorNotes,
                sourceLabel: "Fluke",
                payload: .fluke(sighting)
            )
        }
        let external = (externalState.value ?? []).map { sighting in
            DisplayItem(
                id: "external:\(sighting.id)",
                observedAt: sighting.observedAt,
                latitude: sighting.latitude,
                longitude: sighting.longitude,
                locationName: nil,
                ecotype: sighting.ecotypeGuess,
                groupSize: sighting.groupSize,
                whaleCatalogIDs: [],
                notes: sighting.notes,
                sourceLabel: sighting.attribution,
                payload: .external(sighting)
            )
        }
        return (approved + external).sorted {
            if $0.observedAt == $1.observedAt { return $0.id < $1.id }
            return $0.observedAt > $1.observedAt
        }
    }

    public var isLoading: Bool {
        approvedState.isLoading || externalState.isLoading
    }

    public var hasConfirmedEmptyFeed: Bool {
        isConfirmedEmpty(approvedState) && isConfirmedEmpty(externalState)
    }

    public var primaryFailure: BrowseFailure? {
        approvedState.failure ?? externalState.failure
    }

    public var notices: [BrowseNotice] {
        [approvedState.notice, externalState.notice].compactMap { $0 }
    }

    private func isConfirmedEmpty<Value>(_ state: BrowseViewState<Value>) -> Bool {
        if case .empty = state { return true }
        return false
    }

    private static func loadApproved(
        from repository: any SightingsRepositoryProtocol
    ) async -> BrowseResult<[Sighting]> {
        do {
            return try await repository.loadApproved()
        } catch {
            return .failed(.unexpectedFeatureFailure)
        }
    }

    private static func loadExternal(
        from repository: any SightingsRepositoryProtocol
    ) async -> BrowseResult<[ExternalSighting]> {
        do {
            return try await repository.loadExternal(source: nil, sinceDays: 31)
        } catch {
            return .failed(.unexpectedFeatureFailure)
        }
    }
}
