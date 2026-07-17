import FlukeKit
import Foundation
import Testing

@testable import FlukeFeatures

@MainActor
@Suite("Atlas resilient browse presentation")
struct AtlasBrowseViewModelTests {
    private let metadata = BrowseMetadata(fetchedAt: Date(), schemaVersion: 1)

    @Test("Timeline retains stale historical data and groups tracks by catalog pod")
    func timelineStaleTracks() async {
        let failure = BrowseFailure(code: "TIMEOUT", message: "Refresh timed out.", retryable: true, requestId: nil)
        let sighting = historical(id: "history", whaleIDs: ["whale-j35"])
        let repository = HistoricalRepositoryFake(results: [.stale(
            payload: .value([sighting]), metadata: metadata, failure: failure
        )])
        let model = TimelineViewModel(repository: repository, now: { Date(timeIntervalSince1970: 2_000_000_000) })

        await model.load()

        #expect(model.state.notice == .stale(failure))
        #expect(model.historicalSightings == [sighting])
        let catalog = [makeWhale(id: "whale-j35", catalogId: "J35", name: nil, ecotype: .resident, pod: "J")]
        #expect(model.tracks(catalog: catalog)[.j]?.count == 1)
        #expect(await repository.callCount == 1)
    }

    @Test("Timeline date range remains ordered when the API response is not")
    func timelineDateRangeSortsBounds() async {
        let january = historical(id: "jan", month: 1, whaleIDs: [])
        let february = historical(id: "feb", month: 2, whaleIDs: [])
        let repository = HistoricalRepositoryFake(results: [
            .fresh(value: [february, january], metadata: metadata)
        ])
        let model = TimelineViewModel(repository: repository)

        await model.load()

        #expect(model.dateRange?.lowerBound == january.observedAt)
        #expect(model.dateRange?.upperBound == february.observedAt)
    }

    @Test("Timeline adds one point per pod when a sighting identifies multiple pod members")
    func timelineDeduplicatesPodsWithinSighting() async {
        let sighting = historical(id: "family", whaleIDs: ["whale-j35", "whale-j57"])
        let repository = HistoricalRepositoryFake(results: [
            .fresh(value: [sighting], metadata: metadata)
        ])
        let model = TimelineViewModel(repository: repository)
        let catalog = [
            makeWhale(id: "whale-j35", catalogId: "J35", name: nil, ecotype: .resident, pod: "J"),
            makeWhale(id: "whale-j57", catalogId: "J57", name: nil, ecotype: .resident, pod: "J"),
        ]

        await model.load()

        #expect(model.tracks(catalog: catalog)[.j]?.count == 1)
    }

    @Test("Range retains offline data and filters heat cells by month")
    func rangeOffline() async {
        let january = historical(id: "jan", month: 1, whaleIDs: [])
        let february = historical(id: "feb", month: 2, whaleIDs: [])
        let repository = HistoricalRepositoryFake(results: [.cachedOffline(
            payload: .value([january, february]), metadata: metadata
        )])
        let model = RangeViewModel(repository: repository, now: { Date(timeIntervalSince1970: 2_000_000_000) })

        await model.load()
        model.activeMonths = [1]

        #expect(model.state.notice == .offline)
        #expect(model.sightings.count == 2)
        #expect(model.heatmap.reduce(0) { $0 + $1.count } == 1)
    }

    @Test("Range grid centers remain inside the shared Salish Sea projection")
    func rangeGridProjectionKeepsBoundaryCellsVisible() {
        let projection = SalishSeaProjection.salishSea
        let corners = [
            RangeGridProjection.bin(latitude: projection.north, longitude: projection.west),
            RangeGridProjection.bin(latitude: projection.south, longitude: projection.east),
        ]

        for cell in corners {
            let point = RangeGridProjection.normalizedCenter(x: cell.x, y: cell.y)
            #expect((0...1).contains(point.x))
            #expect((0...1).contains(point.y))
        }
        #expect(corners[0].x == 0)
        #expect(corners[0].y == 0)
        #expect(corners[1].x == RangeGridProjection.columnCount - 1)
        #expect(corners[1].y == RangeGridProjection.rowCount - 1)
    }

    @Test("Changing range pod clears data attributed to the previous pod")
    func rangeQueryChangeClearsContent() async {
        let repository = HistoricalRepositoryFake(results: [
            .fresh(value: [historical(id: "j", whaleIDs: [])], metadata: metadata)
        ])
        let model = RangeViewModel(repository: repository)

        await model.load()
        model.selectedPod = .k

        #expect(model.state == .idle)
        #expect(model.sightings.isEmpty)
    }

    @Test("Trace loads cached tracks, sorts them, and reports sparse truth")
    func traceOfflineSparse() async {
        let points = [
            movement(id: "later", time: 200),
            movement(id: "earlier", time: 100),
        ]
        let repository = WhalesRepositoryFake(tracks: [.cachedOffline(
            payload: .value(points), metadata: metadata
        )])
        let model = TraceViewModel(repository: repository, now: { Date(timeIntervalSince1970: 2_000_000_000) })
        model.selectedWhaleId = "whale-j35"

        await model.loadIfNeeded()

        #expect(model.points.map(\.id) == ["earlier", "later"])
        #expect(model.state.notice == .offline)
        #expect(model.isSparse)
    }

    @Test("Changing trace whale clears the previous whale's track")
    func traceQueryChangeClearsContent() async {
        let repository = WhalesRepositoryFake(tracks: [
            .fresh(value: [movement(id: "j35", time: 100)], metadata: metadata)
        ])
        let model = TraceViewModel(repository: repository, selectedWhaleID: "whale-j35")

        await model.loadIfNeeded()
        model.selectedWhaleId = "whale-j57"

        #expect(model.state == .idle)
        #expect(model.points.isEmpty)
    }

    @Test("Prediction uses cached load and preserves stale prediction")
    func predictionStale() async {
        let prediction = Prediction(
            cells: [PredictionCell(lat: 48.5, lng: -123.2, probability: 0.8)],
            confidence: 0.7,
            modelVersion: "seasonal-v1",
            computedAt: Date()
        )
        let failure = BrowseFailure(code: "TIMEOUT", message: "Refresh timed out.", retryable: true, requestId: nil)
        let repository = PredictionRepositoryFake(results: [.stale(
            payload: .value(prediction), metadata: metadata, failure: failure
        )])
        let model = PredictViewModel(repository: repository)
        model.subject = .pod(.j)

        await model.loadIfNeeded()

        #expect(model.prediction == prediction)
        #expect(model.state.notice == .stale(failure))
        #expect(await repository.callCount == 1)
    }

    @Test("Changing prediction parameters clears cells for the previous query")
    func predictionQueryChangeClearsContent() async {
        let prediction = Prediction(
            cells: [PredictionCell(lat: 48.5, lng: -123.2, probability: 0.8)],
            confidence: 0.7,
            modelVersion: "seasonal-v1",
            computedAt: Date()
        )
        let repository = PredictionRepositoryFake(results: [
            .fresh(value: prediction, metadata: metadata)
        ])
        let model = PredictViewModel(repository: repository)
        model.subject = .pod(.j)

        await model.loadIfNeeded()
        model.horizon = .d7

        #expect(model.state == .idle)
        #expect(model.prediction == nil)
    }

    @Test("Atlas loads a real cached whale catalog")
    func atlasCatalog() async {
        let whale = makeWhale(id: "whale-j35", catalogId: "J35", name: nil, ecotype: .resident, pod: "J")
        let repository = WhalesRepositoryFake(catalog: [.cachedOffline(
            payload: .value([whale]), metadata: metadata
        )])
        let model = AtlasViewModel(repository: repository)

        await model.loadCatalog()

        #expect(model.catalog == [whale])
        #expect(model.catalogState.notice == .offline)
    }

    private func historical(
        id: String,
        month: Int = 1,
        whaleIDs: [String]
    ) -> HistoricalSighting {
        let date = Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2026, month: month, day: 15)
        )!
        return HistoricalSighting(
            id: id, observedAt: date, latitude: 48.5, longitude: -123.2,
            locationName: "Salish Sea", ecotypeGuess: .resident, whaleIds: whaleIDs
        )
    }

    private func movement(id: String, time: TimeInterval) -> MovementTrackPoint {
        MovementTrackPoint(
            id: id, observedAt: Date(timeIntervalSince1970: time), latitude: 48.5,
            longitude: -123.2, locationName: "Salish Sea", behaviorNotes: nil
        )
    }
}

private actor HistoricalRepositoryFake: HistoricalSightingsRepositoryProtocol {
    private var results: [BrowseResult<[HistoricalSighting]>]
    private(set) var callCount = 0

    init(results: [BrowseResult<[HistoricalSighting]>]) {
        self.results = results
    }

    func load(from: Date, to: Date, pod: Pod?) async throws -> BrowseResult<[HistoricalSighting]> {
        callCount += 1
        return results.removeFirst()
    }
}

private actor PredictionRepositoryFake: PredictionRepositoryProtocol {
    private var results: [BrowseResult<Prediction?>]
    private(set) var callCount = 0

    init(results: [BrowseResult<Prediction?>]) {
        self.results = results
    }

    func load(
        subject: PredictionRepository.Subject,
        horizon: PredictionHorizon
    ) async throws -> BrowseResult<Prediction?> {
        callCount += 1
        return results.removeFirst()
    }
}
