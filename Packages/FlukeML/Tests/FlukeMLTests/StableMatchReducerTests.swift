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
    #expect(first.prominent == nil)
    #expect(second.prominent == nil)
    #expect(third.prominent?.catalogID == first.matches.first?.catalogID)
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
}
