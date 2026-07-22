import FlukeKit
import Foundation
import Testing

@testable import FlukeFeatures

@MainActor
@Suite("Whale catalog presentation")
struct WhalesViewModelTests {
    @Test("the same canonical whale can produce a fresh profile request")
    func repeatedCanonicalProfileRequest() {
        let first = WhaleProfileRequest.next(whaleID: "canonical-whale-id", after: nil)
        let second = WhaleProfileRequest.next(whaleID: "canonical-whale-id", after: first)

        #expect(first.whaleID == second.whaleID)
        #expect(first != second)
        #expect(second.revision == first.revision + 1)
    }

    @Test("canonical whale IDs resolve the profile navigation value")
    func canonicalProfileLookup() async {
        let whale = makeWhale(
            id: "canonical-whale-id",
            catalogId: "J35",
            name: "Tahlequah",
            ecotype: .resident,
            pod: "J"
        )
        let model = WhalesViewModel(
            repository: WhalesRepositoryFake(
                catalog: [
                    .fresh(
                        value: [whale],
                        metadata: BrowseMetadata(fetchedAt: Date(), schemaVersion: 1)
                    )
                ]
            )
        )

        await model.load()

        #expect(model.whale(id: "canonical-whale-id") == whale)
        #expect(model.whale(id: "J35") == nil)
    }

    private let metadata = BrowseMetadata(fetchedAt: Date(), schemaVersion: 1)

    @Test("Catalog sorts stably and search spans identity, pod, and ecotype")
    func searchAndSort() async {
        let whales = [
            makeWhale(id: "2", catalogId: "T49A", name: "Noah", ecotype: .biggs, pod: nil),
            makeWhale(id: "1", catalogId: "J35", name: "Tahlequah", ecotype: .resident, pod: "J"),
            makeWhale(id: "3", catalogId: "K12", name: nil, ecotype: .resident, pod: "K"),
        ]
        let repository = WhalesRepositoryFake(catalog: [.fresh(value: whales, metadata: metadata)])
        let model = WhalesViewModel(repository: repository)

        await model.load()
        #expect(model.filteredWhales.map(\.catalogId) == ["J35", "K12", "T49A"])

        model.searchText = "tahle"
        #expect(model.filteredWhales.map(\.catalogId) == ["J35"])
        model.searchText = "bigg"
        #expect(model.filteredWhales.map(\.catalogId) == ["T49A"])
        model.searchText = "K"
        #expect(model.filteredWhales.map(\.catalogId) == ["K12"])
    }

    @Test("Every catalog filter selects only its ecotype")
    func filters() async {
        let whales = Ecotype.allCases.enumerated().map { index, ecotype in
            makeWhale(
                id: String(index),
                catalogId: "W\(index)",
                name: nil,
                ecotype: ecotype,
                pod: nil
            )
        }
        let repository = WhalesRepositoryFake(catalog: [.fresh(value: whales, metadata: metadata)])
        let model = WhalesViewModel(repository: repository)
        await model.load()

        for filter in WhalesViewModel.Filter.allCases where filter != .all {
            model.filter = filter
            #expect(model.filteredWhales.map(\.ecotype) == [filter.ecotype!])
        }
    }

    @Test("Cached catalog remains visible while stale, offline, and refreshing")
    func cachedStates() async {
        let whale = makeWhale(id: "1", catalogId: "J35", name: "Tahlequah", ecotype: .resident, pod: "J")
        let failure = BrowseFailure(
            code: "TIMEOUT",
            message: "The request took too long.",
            retryable: true,
            requestId: nil
        )
        let staleRepository = WhalesRepositoryFake(catalog: [.stale(
            payload: .value([whale]), metadata: metadata, failure: failure
        )])
        let staleModel = WhalesViewModel(repository: staleRepository)
        await staleModel.load()
        #expect(staleModel.filteredWhales == [whale])
        #expect(staleModel.state.notice == .stale(failure))

        let offlineRepository = WhalesRepositoryFake(catalog: [.cachedOffline(
            payload: .value([whale]), metadata: metadata
        )])
        let offlineModel = WhalesViewModel(repository: offlineRepository)
        await offlineModel.load()
        #expect(offlineModel.filteredWhales == [whale])
        #expect(offlineModel.state.notice == .offline)
    }

    @Test("Cached catalog renders before staged network refresh completes")
    func cachedCatalogRendersFirst() async {
        let cached = makeWhale(
            id: "cached", catalogId: "J35", name: nil, ecotype: .resident, pod: "J"
        )
        let fresh = makeWhale(
            id: "fresh", catalogId: "T49A", name: nil, ecotype: .biggs, pod: nil
        )
        let (updates, continuation) = AsyncThrowingStream<BrowseResult<[Whale]>, Error>
            .makeStream()
        let repository = StagedWhalesRepository(updates: updates)
        let model = WhalesViewModel(repository: repository)
        let load = Task { await model.load() }

        continuation.yield(.cached(payload: .value([cached]), metadata: metadata))
        for _ in 0..<20 { await Task.yield() }
        #expect(model.filteredWhales.map(\.id) == ["cached"])

        continuation.yield(.fresh(value: [fresh], metadata: metadata))
        continuation.finish()
        await load.value
        #expect(model.filteredWhales.map(\.id) == ["fresh"])
    }

    @Test("Retry loads catalog again")
    func retry() async {
        let repository = WhalesRepositoryFake(catalog: [
            .empty(metadata: metadata),
            .fresh(
                value: [makeWhale(id: "1", catalogId: "J35", name: nil, ecotype: .resident, pod: "J")],
                metadata: metadata
            ),
        ])
        let model = WhalesViewModel(repository: repository)
        await model.load()
        await model.retry()

        #expect(model.filteredWhales.map(\.catalogId) == ["J35"])
        #expect(await repository.catalogCallCount == 2)
    }
}

private struct StagedWhalesRepository: WhalesRepositoryProtocol {
    let updates: AsyncThrowingStream<BrowseResult<[Whale]>, Error>

    func loadCatalog() async throws -> BrowseResult<[Whale]> {
        return .failed(BrowseFailure(
            code: "ONE_SHOT_USED", message: "Wrong repository path.",
            retryable: false, requestId: nil
        ))
    }

    func catalogUpdates() -> AsyncThrowingStream<BrowseResult<[Whale]>, Error> {
        updates
    }

    func loadProfile(id: String) async throws -> BrowseResult<WhaleProfile?> {
        .empty(metadata: BrowseMetadata(fetchedAt: Date(), schemaVersion: 1))
    }

    func loadTrack(
        whaleId: String, from: Date, to: Date
    ) async throws -> BrowseResult<[MovementTrackPoint]> {
        .empty(metadata: BrowseMetadata(fetchedAt: Date(), schemaVersion: 1))
    }
}

func makeWhale(
    id: String,
    catalogId: String,
    name: String?,
    ecotype: Ecotype,
    pod: String?
) -> Whale {
    Whale(
        id: id, catalogId: catalogId, name: name, ecotype: ecotype, pod: pod,
        sex: .unknown, birthYear: 1998, deathYear: nil, status: .alive,
        biography: "A known Salish Sea orca.", distinguishingMarks: nil,
        heroImageUrl: nil, notableEvents: [], sourceCitations: []
    )
}

actor WhalesRepositoryFake: WhalesRepositoryProtocol {
    private var catalogResults: [BrowseResult<[Whale]>]
    private var profileResults: [BrowseResult<WhaleProfile?>]
    private var trackResults: [BrowseResult<[MovementTrackPoint]>]
    private(set) var catalogCallCount = 0
    private(set) var profileIDs: [String] = []

    init(
        catalog: [BrowseResult<[Whale]>] = [],
        profiles: [BrowseResult<WhaleProfile?>] = [],
        tracks: [BrowseResult<[MovementTrackPoint]>] = []
    ) {
        catalogResults = catalog
        profileResults = profiles
        trackResults = tracks
    }

    func loadCatalog() async throws -> BrowseResult<[Whale]> {
        let index = catalogCallCount
        catalogCallCount += 1
        return catalogResults[min(index, catalogResults.count - 1)]
    }

    func loadProfile(id: String) async throws -> BrowseResult<WhaleProfile?> {
        profileIDs.append(id)
        return profileResults.removeFirst()
    }

    func loadTrack(
        whaleId: String,
        from: Date,
        to: Date
    ) async throws -> BrowseResult<[MovementTrackPoint]> {
        trackResults.removeFirst()
    }
}
