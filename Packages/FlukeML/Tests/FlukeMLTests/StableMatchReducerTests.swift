import Testing

@testable import FlukeML

@Suite("Stable local matching")
struct StableMatchReducerTests {
  @Test("promotes only three consistent eligible frames out of five")
  func promotesThreeOfFive() {
    let reducer = StableMatchReducer(
      scoreThreshold: 0.72,
      marginThreshold: 0.08,
      requiredWins: 3,
      windowSize: 5
    )
    let identifiers = ["J35", "J27", "J35", "J35", "J27"]
    let state = identifiers.reduce(reducer.initialState) { state, identifier in
      reducer.reduce(
        state: state,
        candidate: Self.candidate(identifier, score: 0.82)
      )
    }

    #expect(state.prominent?.catalogID == "J35")
    #expect(state.history.count == 5)
  }

  @Test("does not promote candidates below score or margin thresholds")
  func requiresScoreAndMargin() {
    let reducer = StableMatchReducer(
      scoreThreshold: 0.72,
      marginThreshold: 0.08,
      requiredWins: 3,
      windowSize: 5
    )
    let first = Self.candidate("J35", score: 0.82)

    #expect(!reducer.isEligible(first: Self.candidate("J35", score: 0.71), second: nil))
    #expect(!reducer.isEligible(first: first, second: Self.candidate("J27", score: 0.75)))
    #expect(reducer.isEligible(first: first, second: Self.candidate("J27", score: 0.74)))
  }

  @Test("an ineligible frame occupies the bounded stabilization window")
  func ineligibleFrameBreaksStability() {
    let reducer = StableMatchReducer(
      scoreThreshold: 0.72,
      marginThreshold: 0.08,
      requiredWins: 3,
      windowSize: 5
    )
    let candidates: [LocalMatch?] = [
      Self.candidate("J35"),
      Self.candidate("J35"),
      nil,
      Self.candidate("J27"),
      Self.candidate("J27"),
    ]
    let state = candidates.reduce(reducer.initialState) {
      reducer.reduce(state: $0, candidate: $1)
    }

    #expect(state.prominent == nil)
    #expect(state.history.count == 5)
  }

  @Test("bounds even an oversized internal history before appending")
  func boundsOversizedInternalHistory() {
    let reducer = StableMatchReducer(
      scoreThreshold: 0.72,
      marginThreshold: 0.08,
      requiredWins: 3,
      windowSize: 5
    )
    let oversized = StableMatchState(
      history: [LocalMatch?](repeating: Self.candidate("old"), count: 10_000),
      prominent: nil
    )

    let updated = reducer.reduce(state: oversized, candidate: Self.candidate("new"))

    #expect(updated.history.count == 5)
    #expect(updated.history.last??.catalogID == "new")
  }

  @Test("equal win counts resolve to the most recently observed catalog")
  func equalWinsPreferMostRecentOccurrence() {
    let reducer = StableMatchReducer(
      scoreThreshold: 0.72,
      marginThreshold: 0.08,
      requiredWins: 2,
      windowSize: 4
    )

    let recentB = ["A", "B", "A", "B"].reduce(reducer.initialState) {
      reducer.reduce(state: $0, candidate: Self.candidate($1))
    }
    let recentA = ["B", "A", "B", "A"].reduce(reducer.initialState) {
      reducer.reduce(state: $0, candidate: Self.candidate($1))
    }

    #expect(recentB.prominent?.catalogID == "B")
    #expect(recentA.prominent?.catalogID == "A")
  }

  @Test("identifier embeds, searches, thresholds, and stabilizes through one actor")
  func localIdentifierPipeline() async throws {
    let fixture = try FixtureCatalog()
    defer { fixture.remove() }
    let catalog = try ReferenceCatalog.load(
      directory: fixture.directory,
      compatibility: FixtureCatalog.compatibility,
      appBuild: 42
    )
    let identifier = LocalIdentifier(
      embedder: FixedEmbedder(embedding: FixtureCatalog.queryEmbedding),
      catalog: catalog
    )
    let frame = try CameraFrame(
      pixelBuffer: CoreMLEmbedderTests.redPixelBuffer(),
      orientation: .up
    )

    let first = try await identifier.identify(frame: frame)
    let second = try await identifier.identify(frame: frame)
    let third = try await identifier.identify(frame: frame)

    #expect(first.matches.count == 3)
    #expect(first.artifact.manifestVersion == catalog.manifest.manifestVersion)
    #expect(first.artifact.modelVersion == catalog.manifest.modelVersion)
    #expect(first.artifact.indexVersion == catalog.manifest.indexVersion)
    #expect(first.prominent == nil)
    #expect(second.prominent == nil)
    #expect(third.prominent?.catalogID == first.matches.first?.catalogID)
  }

  @Test("starting a new camera session clears prior stabilization wins")
  func newSessionClearsHistory() async throws {
    let fixture = try FixtureCatalog()
    defer { fixture.remove() }
    let catalog = try ReferenceCatalog.load(
      directory: fixture.directory,
      compatibility: FixtureCatalog.compatibility,
      appBuild: 42
    )
    let identifier = LocalIdentifier(
      embedder: FixedEmbedder(embedding: FixtureCatalog.queryEmbedding),
      catalog: catalog
    )
    let frame = try Self.frame()

    _ = try await identifier.identify(frame: frame)
    _ = try await identifier.identify(frame: frame)
    await identifier.resetSession()
    let reopened = try await identifier.identify(frame: frame)

    #expect(reopened.prominent == nil)
  }

  @Test("an embedding completed after reset cannot mutate the new session")
  func staleEmbeddingCannotCrossSession() async throws {
    let fixture = try FixtureCatalog()
    defer { fixture.remove() }
    let catalog = try ReferenceCatalog.load(
      directory: fixture.directory,
      compatibility: FixtureCatalog.compatibility,
      appBuild: 42
    )
    let embedder = SuspendedThenImmediateEmbedder(embedding: FixtureCatalog.queryEmbedding)
    let identifier = LocalIdentifier(embedder: embedder, catalog: catalog)
    let frame = try Self.frame()
    let stale = Task { try await identifier.identify(frame: frame) }
    await embedder.waitUntilSuspended()

    await identifier.resetSession()
    await embedder.resume()
    await #expect(throws: CancellationError.self) { try await stale.value }
    let first = try await identifier.identify(frame: frame)
    let second = try await identifier.identify(frame: frame)

    #expect(first.prominent == nil)
    #expect(second.prominent == nil)
  }

  @Test(
    "real search candidates rejected by score or margin produce unknown",
    arguments: [
      ["scoreThreshold": 1.0],
      ["marginThreshold": 1.0],
    ]
  )
  func rejectedRealCandidatesAreUnknown(manifestUpdates: [String: Any]) async throws {
    let fixture = try FixtureCatalog(manifestUpdates: manifestUpdates)
    defer { fixture.remove() }
    let catalog = try ReferenceCatalog.load(
      directory: fixture.directory,
      compatibility: FixtureCatalog.compatibility,
      appBuild: 42
    )
    let identifier = LocalIdentifier(
      embedder: FixedEmbedder(embedding: FixtureCatalog.queryEmbedding),
      catalog: catalog
    )

    let state = try await identifier.identify(frame: Self.frame())

    #expect(state.matches.isEmpty)
    #expect(state.prominent == nil)
  }
}

extension StableMatchReducerTests {
  fileprivate struct FixedEmbedder: EmbeddingProviding {
    let embedding: [Float]

    func embedding(frame _: CameraFrame) async throws -> [Float] {
      embedding
    }
  }

  fileprivate static func candidate(_ catalogID: String, score: Float = 0.82) -> LocalMatch {
    LocalMatch(
      catalogID: catalogID,
      whaleID: "whale-\(catalogID)",
      score: score,
      rank: 1,
      matchedReferencePhotoIDs: ["photo-\(catalogID)"]
    )
  }

  fileprivate static func frame() throws -> CameraFrame {
    try CameraFrame(
      pixelBuffer: CoreMLEmbedderTests.redPixelBuffer(),
      orientation: .up
    )
  }
}

private actor SuspendedThenImmediateEmbedder: EmbeddingProviding {
  private let value: [Float]
  private var shouldSuspend = true
  private var continuation: CheckedContinuation<Void, Never>?
  private var waiters: [CheckedContinuation<Void, Never>] = []

  init(embedding: [Float]) { value = embedding }

  func embedding(frame _: CameraFrame) async -> [Float] {
    guard shouldSuspend else { return value }
    shouldSuspend = false
    let ready = waiters
    waiters = []
    for waiter in ready { waiter.resume() }
    await withCheckedContinuation { continuation = $0 }
    return value
  }

  func waitUntilSuspended() async {
    guard shouldSuspend else { return }
    await withCheckedContinuation { waiters.append($0) }
  }

  func resume() {
    continuation?.resume()
    continuation = nil
  }
}
