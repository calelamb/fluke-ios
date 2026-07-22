import FlukeKit
import Foundation
import Observation

public enum AtlasProjection {
  public static let bounds = SalishSeaProjection(
    south: 47.0,
    west: -124.7,
    north: 49.5,
    east: -122.0
  )

  public static func project(latitude: Double, longitude: Double) -> (x: Double, y: Double) {
    let point = bounds.project(lat: latitude, lng: longitude)
    return (
      x: min(max(point.x, 0), 1),
      y: min(max(point.y, 0), 1)
    )
  }
}

public struct AtlasStatusComposition: Equatable, Sendable {
  public let notice: BrowseNotice?
  public let truth: AtlasModeTruth?

  public init(notice: BrowseNotice?, truth: AtlasModeTruth?) {
    self.notice = notice
    self.truth = truth
  }
}

public enum AtlasModeTruth: Equatable, Sendable {
  case empty(String)
  case sparse(String)

  public var message: String {
    switch self {
    case .empty(let message), .sparse(let message): message
    }
  }
}

@MainActor
@Observable
public final class AtlasViewModel {
  public enum SubView: String, CaseIterable, Identifiable {
    case timeline = "Timeline"
    case range = "Range"
    case trace = "Trace"
    case predict = "Predict"

    public var id: String { rawValue }
  }

  public var activeSubView: SubView = .timeline
  public private(set) var catalogState: BrowseViewState<[Whale]> = .idle

  private let repository: any WhalesRepositoryProtocol
  private var loadGeneration = 0

  public init(
    repository: any WhalesRepositoryProtocol,
    activeSubView: SubView = .timeline
  ) {
    self.repository = repository
    self.activeSubView = activeSubView
  }

  public func loadCatalog() async {
    loadGeneration += 1
    let generation = loadGeneration
    catalogState = catalogState.beginRefresh()
    do {
      for try await result in repository.catalogUpdates() {
        guard generation == loadGeneration else { return }
        catalogState = .resolve(result)
      }
    } catch {
      guard generation == loadGeneration else { return }
      catalogState = .failed(.unexpectedFeatureFailure)
    }
  }

  public var catalog: [Whale] {
    catalogState.value ?? []
  }
}
