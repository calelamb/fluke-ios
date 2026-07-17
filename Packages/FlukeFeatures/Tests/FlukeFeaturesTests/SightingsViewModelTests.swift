import FlukeKit
import Foundation
import Testing

@testable import FlukeFeatures

@MainActor
@Suite("Sightings presentation")
struct SightingsViewModelTests {
    private let metadata = BrowseMetadata(
        fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
        schemaVersion: 1
    )

    @Test("Approved and external sightings merge newest first with stable source identity")
    func mergesFeeds() async throws {
        let approved = makeSighting(
            id: "approved",
            time: 200,
            identifiedWhales: [IdentifiedWhale(catalogId: "J35", name: "Tahlequah", confidence: .confirmed)]
        )
        let external = try makeExternal(id: "external", time: 100)
        let repository = SightingsRepositoryFake(
            approved: [.fresh(value: [approved], metadata: metadata)],
            external: [.fresh(value: [external], metadata: metadata)]
        )
        let model = SightingsViewModel(repository: repository)

        await model.load()

        #expect(model.items.map(\.id) == ["fluke:approved", "external:external"])
        #expect(model.items.map(\.sourceLabel) == ["Fluke", "Center for Whale Research"])
        #expect(model.items.first?.whaleCatalogIDs == ["J35"])
    }

    @Test("Stale and offline feeds retain cached content and notices")
    func retainsCachedContent() async throws {
        let failure = BrowseFailure(
            code: "TIMEOUT",
            message: "The request took too long. Try again.",
            retryable: true,
            requestId: nil
        )
        let repository = SightingsRepositoryFake(
            approved: [.stale(
                payload: .value([makeSighting(id: "cached", time: 200)]),
                metadata: metadata,
                failure: failure
            )],
            external: [.cachedOffline(
                payload: .value([try makeExternal(id: "offline", time: 100)]),
                metadata: metadata
            )]
        )
        let model = SightingsViewModel(repository: repository)

        await model.load()

        #expect(model.items.count == 2)
        #expect(model.approvedState.notice == .stale(failure))
        #expect(model.externalState.notice == .offline)
    }

    @Test("Server empty and failed states remain distinct")
    func distinguishesEmptyAndFailed() async {
        let failure = BrowseFailure(
            code: "SERVICE_UNAVAILABLE",
            message: "Sightings are unavailable right now.",
            retryable: true,
            requestId: nil
        )
        let repository = SightingsRepositoryFake(
            approved: [.empty(metadata: metadata)],
            external: [.failed(failure)]
        )
        let model = SightingsViewModel(repository: repository)

        await model.load()

        #expect(model.items.isEmpty)
        #expect(!model.hasConfirmedEmptyFeed)
        #expect(model.primaryFailure == failure)
    }

    @Test("Retry reloads both public feeds")
    func retry() async {
        let repository = SightingsRepositoryFake(
            approved: [
                .empty(metadata: metadata),
                .fresh(value: [makeSighting(id: "new", time: 300)], metadata: metadata),
            ],
            external: [
                .empty(metadata: metadata),
                .empty(metadata: metadata),
            ]
        )
        let model = SightingsViewModel(repository: repository)

        await model.load()
        await model.retry()

        #expect(model.items.map(\.id) == ["fluke:new"])
        #expect(await repository.approvedCallCount == 2)
        #expect(await repository.externalCallCount == 2)
    }

    @Test("A slower older load cannot replace a newer response")
    func latestLoadWins() async {
        let repository = SightingsRepositoryFake(
            approved: [
                .fresh(value: [makeSighting(id: "old", time: 100)], metadata: metadata),
                .fresh(value: [makeSighting(id: "new", time: 200)], metadata: metadata),
            ],
            external: [
                .empty(metadata: metadata),
                .empty(metadata: metadata),
            ],
            approvedDelays: [.milliseconds(120), .milliseconds(5)],
            externalDelays: [.milliseconds(120), .milliseconds(5)]
        )
        let model = SightingsViewModel(repository: repository)

        let first = Task { await model.load() }
        try? await Task.sleep(for: .milliseconds(10))
        let second = Task { await model.load() }
        await second.value
        await first.value

        #expect(model.items.map(\.id) == ["fluke:new"])
    }

    private func makeSighting(
        id: String,
        time: TimeInterval,
        identifiedWhales: [IdentifiedWhale] = []
    ) -> Sighting {
        Sighting(
            id: id,
            observedAt: Date(timeIntervalSince1970: time),
            latitude: 48.5,
            longitude: -123.2,
            locationName: "Salish Sea",
            ecotypeGuess: .resident,
            groupSize: 4,
            behaviorNotes: "Traveling north",
            status: .approved,
            photoUrls: [],
            photos: [],
            identifiedWhales: identifiedWhales
        )
    }

    private func makeExternal(id: String, time: TimeInterval) throws -> ExternalSighting {
        let date = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: time))
        let json = """
        {
          "id":"\(id)","source":"CWR","externalId":"source-\(id)",
          "observedAt":"\(date)","latitude":48.4,"longitude":-123.1,
          "species":"Orcinus orca","ecotypeGuess":"RESIDENT","groupSize":3,
          "attribution":"Center for Whale Research","sourceUrl":"https://example.org/source",
          "notes":"Observed from shore","trusted":true
        }
        """
        return try JSONDecoder.fluke.decode(ExternalSighting.self, from: Data(json.utf8))
    }
}

private actor SightingsRepositoryFake: SightingsRepositoryProtocol {
    private var approvedResults: [BrowseResult<[Sighting]>]
    private var externalResults: [BrowseResult<[ExternalSighting]>]
    private var approvedDelays: [Duration]
    private var externalDelays: [Duration]
    private(set) var approvedCallCount = 0
    private(set) var externalCallCount = 0

    init(
        approved: [BrowseResult<[Sighting]>],
        external: [BrowseResult<[ExternalSighting]>],
        approvedDelays: [Duration] = [],
        externalDelays: [Duration] = []
    ) {
        self.approvedResults = approved
        self.externalResults = external
        self.approvedDelays = approvedDelays
        self.externalDelays = externalDelays
    }

    func loadApproved() async throws -> BrowseResult<[Sighting]> {
        let index = approvedCallCount
        approvedCallCount += 1
        let result = approvedResults[min(index, approvedResults.count - 1)]
        let delay = index < approvedDelays.count ? approvedDelays[index] : .zero
        try await Task.sleep(for: delay)
        return result
    }

    func loadExternal(source: String?, sinceDays: Int) async throws -> BrowseResult<[ExternalSighting]> {
        let index = externalCallCount
        externalCallCount += 1
        let result = externalResults[min(index, externalResults.count - 1)]
        let delay = index < externalDelays.count ? externalDelays[index] : .zero
        try await Task.sleep(for: delay)
        return result
    }
}
