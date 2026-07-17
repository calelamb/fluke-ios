import FlukeKit
import Foundation
import Testing

@testable import FlukeFeatures

@MainActor
@Suite("Atlas product contract")
struct AtlasProductTests {
  private let metadata = BrowseMetadata(
    fetchedAt: Date(timeIntervalSince1970: 1_768_435_200),
    schemaVersion: 1
  )

  @Test("Atlas defaults to Timeline and exposes the approved mode order")
  func atlasModes() {
    #expect(
      AtlasViewModel.SubView.allCases.map(\.rawValue) == ["Timeline", "Range", "Trace", "Predict"])
    #expect(AtlasViewModel(repository: AtlasWhalesFixture()).activeSubView == .timeline)
  }

  @Test("Atlas uses fixed Salish Sea bounds and clamps projected coordinates")
  func salishProjection() {
    #expect(AtlasProjection.bounds.south == 47.0)
    #expect(AtlasProjection.bounds.west == -124.7)
    #expect(AtlasProjection.bounds.north == 49.5)
    #expect(AtlasProjection.bounds.east == -122.0)
    #expect(AtlasProjection.project(latitude: 50.5, longitude: -126).x == 0)
    #expect(AtlasProjection.project(latitude: 50.5, longitude: -126).y == 0)
    #expect(AtlasProjection.project(latitude: 46, longitude: -121).x == 1)
    #expect(AtlasProjection.project(latitude: 46, longitude: -121).y == 1)
  }

  @Test("Timeline composes date and pod filtering into its summary")
  func timelineComposition() async {
    let repository = AtlasHistoryFixture(
      result: .fresh(
        value: [
          historical(id: "january", month: 1, whaleIDs: ["J35"]),
          historical(id: "february", month: 2, whaleIDs: ["K12"]),
        ],
        metadata: metadata
      ))
    let model = TimelineViewModel(repository: repository)
    await model.load()
    model.scrubberDate = historical(id: "cutoff", month: 1, whaleIDs: []).observedAt
    model.activePods = [.j]

    let catalog = [
      whale(id: "j35", catalogID: "J35", pod: "J"),
      whale(id: "k12", catalogID: "K12", pod: "K"),
    ]

    #expect(model.tracks(catalog: catalog)[.j]?.count == 1)
    #expect(model.tracks(catalog: catalog)[.k] == nil)
    #expect(model.accessibilitySummary(catalog: catalog).contains("J pod"))
    #expect(model.accessibilitySummary(catalog: catalog).contains("1 sighting"))
  }

  @Test("Pod styling remains stable across every Atlas mode")
  func podStyleMapping() {
    #expect(Pod.allCases.map { AtlasPodColor.token(for: $0) } == [.tide, .deep, .swell, .ember])
  }

  @Test("Range composes month and pod filters and normalizes empty heatmaps safely")
  func rangeComposition() async {
    let repository = AtlasHistoryFixture(
      result: .fresh(
        value: [
          historical(id: "january", month: 1, whaleIDs: []),
          historical(id: "february", month: 2, whaleIDs: []),
        ],
        metadata: metadata
      ))
    let model = RangeViewModel(repository: repository)
    await model.load()
    model.activeMonths = [1]

    #expect(model.heatmap.reduce(0) { $0 + $1.count } == 1)
    #expect(model.accessibilitySummary.contains("J pod"))
    #expect(model.accessibilitySummary.contains("January"))
    #expect(RangeHeatmapPresentation.intensity(count: 0, maximum: 0) == 0)
    #expect(RangeHeatmapPresentation.intensity(count: 3, maximum: 2) == 1)
  }

  @Test("Trace selection keeps whale identity and summarizes the chosen animal")
  func traceIdentity() async {
    let selected = whale(id: "stable-id", catalogID: "J35", pod: "J")
    let repository = AtlasWhalesFixture(
      track: .fresh(
        value: [
          movement(id: "a", time: 100), movement(id: "b", time: 200), movement(id: "c", time: 300),
        ],
        metadata: metadata
      )
    )
    let model = TraceViewModel(repository: repository, selectedWhaleID: selected.id)
    await model.loadIfNeeded()

    #expect(model.selectedWhaleId == "stable-id")
    #expect(model.accessibilitySummary(catalog: [selected]).contains("J35"))
    #expect(model.accessibilitySummary(catalog: [selected]).contains("3 sightings"))
  }

  @Test("Predict supports whale and pod subjects with bounded confidence")
  func predictionSubjects() async {
    let prediction = Prediction(
      cells: [PredictionCell(lat: 48.5, lng: -123.2, probability: 0.7)],
      confidence: 1.8,
      modelVersion: "seasonal-v1",
      computedAt: Date(timeIntervalSince1970: 1_768_435_200)
    )
    let repository = AtlasPredictionFixture(result: .fresh(value: prediction, metadata: metadata))
    let model = PredictViewModel(repository: repository)
    model.subject = .whale(id: "J35")
    await model.loadIfNeeded()

    #expect(await repository.lastSubjectDescription == "whale:J35")
    #expect(model.normalizedConfidence == 1)
    model.subject = .pod(.j)
    #expect(model.subject == .pod(.j))
  }

  @Test("Predict copy never represents an estimate as a live location")
  func predictionFraming() {
    let prediction = Prediction(
      cells: [PredictionCell(lat: 48.5, lng: -123.2, probability: 0.7)],
      confidence: 0.6,
      modelVersion: "seasonal-v1",
      computedAt: Date(timeIntervalSince1970: 1_768_435_200)
    )
    let copy = PredictPresentation.summary(prediction, subjectName: "J pod")

    #expect(copy.contains("based on historical sightings"))
    #expect(!copy.localizedCaseInsensitiveContains("will be"))
    #expect(!copy.localizedCaseInsensitiveContains("live location"))
  }

  @Test("Prediction cells are clamped to the fixed Atlas viewport")
  func predictionCellClamping() {
    let cells = PredictPresentation.clampedCells([
      PredictionCell(lat: 52, lng: -130, probability: 0.7),
      PredictionCell(lat: 44, lng: -119, probability: 0.2),
    ])

    #expect(cells[0].lat == AtlasProjection.bounds.north)
    #expect(cells[0].lng == AtlasProjection.bounds.west)
    #expect(cells[1].lat == AtlasProjection.bounds.south)
    #expect(cells[1].lng == AtlasProjection.bounds.east)
  }

  @Test("Timeline composes cached-offline notice with empty truth")
  func timelineOfflineEmptyComposition() async {
    let model = TimelineViewModel(
      repository: AtlasHistoryFixture(result: .cachedOffline(payload: .empty, metadata: metadata))
    )

    await model.load()

    #expect(model.statusComposition.notice == .offline)
    #expect(model.statusComposition.truth == .empty("No historical sightings in this window."))
  }

  @Test("Timeline composes stale notice with empty truth")
  func timelineStaleEmptyComposition() async {
    let failure = staleFailure()
    let model = TimelineViewModel(
      repository: AtlasHistoryFixture(
        result: .stale(payload: .empty, metadata: metadata, failure: failure)
      )
    )

    await model.load()

    #expect(model.statusComposition.notice == .stale(failure))
    #expect(model.statusComposition.truth == .empty("No historical sightings in this window."))
  }

  @Test("Range composes cached-offline notice with empty truth")
  func rangeOfflineEmptyComposition() async {
    let model = RangeViewModel(
      repository: AtlasHistoryFixture(result: .cachedOffline(payload: .empty, metadata: metadata))
    )

    await model.load()

    #expect(model.statusComposition.notice == .offline)
    #expect(model.statusComposition.truth == .empty("No range data for this pod and window."))
  }

  @Test("Range composes stale notice with empty truth")
  func rangeStaleEmptyComposition() async {
    let failure = staleFailure()
    let model = RangeViewModel(
      repository: AtlasHistoryFixture(
        result: .stale(payload: .empty, metadata: metadata, failure: failure)
      )
    )

    await model.load()

    #expect(model.statusComposition.notice == .stale(failure))
    #expect(model.statusComposition.truth == .empty("No range data for this pod and window."))
  }

  @Test("Trace composes cached-offline notice with empty truth")
  func traceOfflineEmptyComposition() async {
    let model = TraceViewModel(
      repository: AtlasWhalesFixture(
        track: .cachedOffline(payload: .empty, metadata: metadata)
      ),
      selectedWhaleID: "J35"
    )

    await model.loadIfNeeded()

    #expect(model.statusComposition(hasCatalog: true).notice == .offline)
    #expect(
      model.statusComposition(hasCatalog: true).truth
        == .empty("No movement points were returned for this whale."))
  }

  @Test("Trace composes stale notice with sparse truth")
  func traceStaleSparseComposition() async {
    let failure = staleFailure()
    let model = TraceViewModel(
      repository: AtlasWhalesFixture(
        track: .stale(
          payload: .value([movement(id: "one", time: 100)]),
          metadata: metadata,
          failure: failure
        )
      ),
      selectedWhaleID: "J35"
    )

    await model.loadIfNeeded()

    #expect(model.statusComposition(hasCatalog: true).notice == .stale(failure))
    #expect(
      model.statusComposition(hasCatalog: true).truth
        == .sparse("Not enough sightings yet to trace a movement pattern."))
  }

  @Test("Predict composes cached-offline notice with empty truth")
  func predictOfflineEmptyComposition() async {
    let model = PredictViewModel(
      repository: AtlasPredictionFixture(
        result: .cachedOffline(payload: .empty, metadata: metadata)
      ))
    model.subject = .pod(.j)

    await model.loadIfNeeded()

    #expect(model.statusComposition.notice == .offline)
    #expect(
      model.statusComposition.truth
        == .empty("Not enough data to show a prediction for this subject and horizon."))
  }

  @Test("Predict composes stale notice with empty truth")
  func predictStaleEmptyComposition() async {
    let failure = staleFailure()
    let model = PredictViewModel(
      repository: AtlasPredictionFixture(
        result: .stale(payload: .empty, metadata: metadata, failure: failure)
      ))
    model.subject = .pod(.j)

    await model.loadIfNeeded()

    #expect(model.statusComposition.notice == .stale(failure))
    #expect(
      model.statusComposition.truth
        == .empty("Not enough data to show a prediction for this subject and horizon."))
  }

  @Test("Predict snapshot state preserves its selected subject and offline empty truth")
  func predictInitialComposition() {
    let model = PredictViewModel(
      repository: AtlasPredictionFixture(
        result: .cachedOffline(payload: .empty, metadata: metadata)
      ),
      initialState: .empty(notice: .offline, isRefreshing: false),
      initialSubject: .pod(.j)
    )

    #expect(model.subject == .pod(.j))
    #expect(model.statusComposition.notice == .offline)
    #expect(model.statusComposition.truth != nil)
  }

  @Test("Flowing dashed paths stop when Reduce Motion is enabled")
  func reducedMotionPath() {
    #expect(AnimatedPolylineLayer.dashPattern(drawComplete: true, reduceMotion: false) == [8, 6])
    #expect(AnimatedPolylineLayer.dashPattern(drawComplete: true, reduceMotion: true).isEmpty)
    #expect(AnimatedPolylineLayer.dashPattern(drawComplete: false, reduceMotion: false).isEmpty)
  }

  private func historical(id: String, month: Int, whaleIDs: [String]) -> HistoricalSighting {
    let date = Calendar(identifier: .gregorian).date(
      from: DateComponents(year: 2026, month: month, day: 15)
    )!
    return HistoricalSighting(
      id: id,
      observedAt: date,
      latitude: 48.5,
      longitude: -123.2,
      locationName: "Salish Sea",
      ecotypeGuess: .resident,
      whaleIds: whaleIDs
    )
  }

  private func movement(id: String, time: TimeInterval) -> MovementTrackPoint {
    MovementTrackPoint(
      id: id,
      observedAt: Date(timeIntervalSince1970: time),
      latitude: 48.5,
      longitude: -123.2,
      locationName: "Salish Sea",
      behaviorNotes: nil
    )
  }

  private func whale(id: String, catalogID: String, pod: String) -> Whale {
    makeWhale(id: id, catalogId: catalogID, name: nil, ecotype: .resident, pod: pod)
  }

  private func staleFailure() -> BrowseFailure {
    BrowseFailure(
      code: "STALE",
      message: "Showing saved Atlas data.",
      retryable: true,
      requestId: nil
    )
  }
}

private actor AtlasHistoryFixture: HistoricalSightingsRepositoryProtocol {
  let result: BrowseResult<[HistoricalSighting]>

  init(result: BrowseResult<[HistoricalSighting]>) {
    self.result = result
  }

  func load(from: Date, to: Date, pod: Pod?) async throws -> BrowseResult<[HistoricalSighting]> {
    result
  }
}

private actor AtlasWhalesFixture: WhalesRepositoryProtocol {
  let catalog: BrowseResult<[Whale]>
  let track: BrowseResult<[MovementTrackPoint]>

  init(
    catalog: BrowseResult<[Whale]> = .empty(
      metadata: BrowseMetadata(fetchedAt: Date(), schemaVersion: 1)),
    track: BrowseResult<[MovementTrackPoint]> = .empty(
      metadata: BrowseMetadata(fetchedAt: Date(), schemaVersion: 1))
  ) {
    self.catalog = catalog
    self.track = track
  }

  func loadCatalog() async throws -> BrowseResult<[Whale]> { catalog }
  func loadProfile(id: String) async throws -> BrowseResult<WhaleProfile?> {
    .empty(metadata: BrowseMetadata(fetchedAt: Date(), schemaVersion: 1))
  }
  func loadTrack(whaleId: String, from: Date, to: Date) async throws -> BrowseResult<
    [MovementTrackPoint]
  > {
    track
  }
}

private actor AtlasPredictionFixture: PredictionRepositoryProtocol {
  let result: BrowseResult<Prediction?>
  private(set) var lastSubjectDescription: String?

  init(result: BrowseResult<Prediction?>) {
    self.result = result
  }

  func load(
    subject: PredictionRepository.Subject,
    horizon: PredictionHorizon
  ) async throws -> BrowseResult<Prediction?> {
    switch subject {
    case .whale(let id): lastSubjectDescription = "whale:\(id)"
    case .pod(let pod): lastSubjectDescription = "pod:\(pod.rawValue)"
    }
    return result
  }
}
