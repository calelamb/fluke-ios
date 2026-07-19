import Foundation

public enum LocalIdentifierError: Error, Equatable, LocalizedError, Sendable {
  case modelResourceMissing
  case modelLoadFailed
  case invalidModelContract
  case invalidModelOutput
  case invalidEmbedding
  case invalidPixelBuffer
  case preprocessingFailed
  case predictionFailed

  public var errorDescription: String? {
    switch self {
    case .modelResourceMissing:
      "The on-device identification model is unavailable."
    case .modelLoadFailed, .invalidModelContract:
      "The on-device identification model could not be verified."
    case .invalidModelOutput, .invalidEmbedding:
      "The on-device identification result failed validation."
    case .invalidPixelBuffer, .preprocessingFailed:
      "This camera frame could not be prepared for identification."
    case .predictionFailed:
      "On-device identification could not process this frame."
    }
  }
}

public protocol EmbeddingProviding: Sendable {
  func embedding(frame: CameraFrame) async throws -> [Float]
}

public protocol LocalIdentifying: Sendable {
  func identify(frame: CameraFrame) async throws -> LocalIdentificationState
}

public struct LocalIdentificationState: Equatable, Sendable {
  public let matches: [LocalMatch]
  public let prominent: LocalMatch?

  public init(matches: [LocalMatch], prominent: LocalMatch?) {
    self.matches = matches
    self.prominent = prominent
  }
}

public actor LocalIdentifier: LocalIdentifying {
  private static let resultLimit = 3
  private static let requiredWins = 3
  private static let windowSize = 5

  private let embedder: any EmbeddingProviding
  private let searcher: ExactCosineSearcher
  private let reducer: StableMatchReducer
  private var state: StableMatchState

  public init(embedder: any EmbeddingProviding, catalog: ReferenceCatalog) {
    self.embedder = embedder
    searcher = ExactCosineSearcher(catalog: catalog)
    reducer = StableMatchReducer(
      scoreThreshold: catalog.manifest.scoreThreshold,
      marginThreshold: catalog.manifest.marginThreshold,
      requiredWins: Self.requiredWins,
      windowSize: Self.windowSize
    )
    state = reducer.initialState
  }

  public static func load(bundle: Bundle = .main) async throws -> LocalIdentifier {
    let catalog = try ReferenceCatalog.load(
      bundle: bundle,
      compatibility: CoreMLEmbedder.artifactCompatibility
    )
    let embedder = try await CoreMLEmbedder.load(bundle: bundle)
    return LocalIdentifier(embedder: embedder, catalog: catalog)
  }

  public func identify(frame: CameraFrame) async throws -> LocalIdentificationState {
    let embedding = try await embedder.embedding(frame: frame)
    let matches = try searcher.search(embedding: embedding, limit: Self.resultLimit)
    let eligible = matches.first.flatMap { first in
      reducer.isEligible(first: first, second: matches.dropFirst().first) ? first : nil
    }
    let updatedState = reducer.reduce(state: state, candidate: eligible)
    state = updatedState
    return LocalIdentificationState(matches: matches, prominent: updatedState.prominent)
  }
}
