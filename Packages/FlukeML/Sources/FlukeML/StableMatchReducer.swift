import Foundation

public struct StableMatchState: Equatable, Sendable {
  public let history: [LocalMatch?]
  public let prominent: LocalMatch?

  init(history: [LocalMatch?] = [], prominent: LocalMatch? = nil) {
    self.history = history
    self.prominent = prominent
  }
}

public struct StableMatchReducer: Sendable {
  public let initialState = StableMatchState()

  private let scoreThreshold: Float
  private let marginThreshold: Float
  private let requiredWins: Int
  private let windowSize: Int

  public init(
    scoreThreshold: Float,
    marginThreshold: Float,
    requiredWins: Int = 3,
    windowSize: Int = 5
  ) {
    precondition(scoreThreshold.isFinite && (-1...1).contains(scoreThreshold))
    precondition(marginThreshold.isFinite && (-1...1).contains(marginThreshold))
    precondition(requiredWins > 0 && requiredWins <= windowSize)
    precondition(windowSize > 0)
    self.scoreThreshold = scoreThreshold
    self.marginThreshold = marginThreshold
    self.requiredWins = requiredWins
    self.windowSize = windowSize
  }

  public func isEligible(first: LocalMatch, second: LocalMatch?) -> Bool {
    guard first.score.isFinite, first.score >= scoreThreshold else { return false }
    guard let second else { return true }
    guard second.score.isFinite else { return false }
    return first.score - second.score + Float.ulpOfOne >= marginThreshold
  }

  public func reduce(state: StableMatchState, candidate: LocalMatch?) -> StableMatchState {
    let safeCandidate = candidate.flatMap { $0.score.isFinite ? $0 : nil }
    let retained = state.history.suffix(max(0, windowSize - 1))
    let history = Array(retained) + [safeCandidate]
    let winner = rankedWinner(in: history)
    let prominent = winner.flatMap { identifier in
      history.reversed().compactMap(\.self).first { $0.catalogID == identifier }
    }
    return StableMatchState(history: history, prominent: prominent)
  }

  private func rankedWinner(in history: [LocalMatch?]) -> String? {
    let standings = history.enumerated().reduce([String: Standing]()) { standings, entry in
      guard let match = entry.element else { return standings }
      let previous = standings[match.catalogID]
      var updated = standings
      updated[match.catalogID] = Standing(
        catalogID: match.catalogID,
        wins: (previous?.wins ?? 0) + 1,
        mostRecentIndex: entry.offset
      )
      return updated
    }
    return standings.values
      .filter { $0.wins >= requiredWins }
      .sorted(by: Self.isPreferred)
      .first?.catalogID
  }

  private static func isPreferred(_ lhs: Standing, _ rhs: Standing) -> Bool {
    if lhs.wins != rhs.wins { return lhs.wins > rhs.wins }
    if lhs.mostRecentIndex != rhs.mostRecentIndex {
      return lhs.mostRecentIndex > rhs.mostRecentIndex
    }
    return lhs.catalogID < rhs.catalogID
  }
}

private struct Standing: Sendable {
  let catalogID: String
  let wins: Int
  let mostRecentIndex: Int
}
