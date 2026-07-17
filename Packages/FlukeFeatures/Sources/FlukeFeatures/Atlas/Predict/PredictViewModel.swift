import FlukeKit
import Foundation
import Observation

@MainActor
@Observable
public final class PredictViewModel {

  public enum Subject: Equatable {
    case whale(id: String)
    case pod(_ pod: Pod)
  }

  public private(set) var state: BrowseViewState<Prediction?> = .idle
  public var horizon: PredictionHorizon = .h24 {
    didSet {
      guard horizon != oldValue else { return }
      invalidateQueryState()
    }
  }
  public var subject: Subject? {
    didSet {
      guard subject != oldValue else { return }
      invalidateQueryState()
    }
  }

  private let predictions: any PredictionRepositoryProtocol
  private var loadGeneration = 0

  public init(repository: any PredictionRepositoryProtocol) {
    self.predictions = repository
  }

  init(
    repository: any PredictionRepositoryProtocol,
    initialState: BrowseViewState<Prediction?>,
    initialSubject: Subject?
  ) {
    self.predictions = repository
    subject = initialSubject
    state = initialState
  }

  public func loadIfNeeded() async {
    guard let subject else {
      state = .idle
      return
    }
    loadGeneration += 1
    let generation = loadGeneration
    state = state.beginRefresh()
    let mappedSubject: PredictionRepository.Subject = {
      switch subject {
      case .whale(let id): return .whale(id: id)
      case .pod(let pod): return .pod(pod)
      }
    }()
    let result: BrowseResult<Prediction?>
    do {
      result = try await predictions.load(subject: mappedSubject, horizon: horizon)
    } catch {
      result = .failed(.unexpectedFeatureFailure)
    }
    guard generation == loadGeneration else { return }
    state = .resolve(result)
  }

  public func retry() async { await loadIfNeeded() }

  public var prediction: Prediction? { state.value ?? nil }

  public var normalizedConfidence: Double {
    min(max(prediction?.confidence ?? 0, 0), 1)
  }

  public var isEmpty: Bool {
    if case .empty = state { return true }
    if case .content(nil, _, _) = state { return true }
    return false
  }

  public var statusComposition: AtlasStatusComposition {
    AtlasStatusComposition(
      notice: state.notice,
      truth: isConfirmedEmpty
        ? .empty("Not enough data to show a prediction for this subject and horizon.")
        : nil
    )
  }

  private var isConfirmedEmpty: Bool {
    switch state {
    case .empty: true
    case .content(let prediction, _, _): prediction == nil
    case .idle, .loading, .failed: false
    }
  }

  private func invalidateQueryState() {
    loadGeneration += 1
    state = .idle
  }
}

public enum PredictPresentation {
  public static func clampedCells(_ cells: [PredictionCell]) -> [PredictionCell] {
    cells.map { cell in
      let point = AtlasProjection.project(latitude: cell.lat, longitude: cell.lng)
      let coordinate = AtlasProjection.bounds.unproject(x: point.x, y: point.y)
      return PredictionCell(
        lat: coordinate.lat,
        lng: coordinate.lng,
        probability: cell.probability
      )
    }
  }

  public static func summary(_ prediction: Prediction, subjectName: String) -> String {
    let count = prediction.cells.count
    let cellWord = count == 1 ? "cell" : "cells"
    let confidence = min(max(prediction.confidence, 0), 1)
    let percent = Int((confidence * 100).rounded())
    return
      "Estimated historical pattern for \(subjectName), based on historical sightings: \(count) \(cellWord), \(percent) percent model confidence. This is not a current position."
  }
}
