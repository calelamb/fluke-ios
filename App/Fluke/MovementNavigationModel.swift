import FlukeKit
import FlukeReleaseB
import Foundation
import Observation

enum MovementUnavailableReason: Equatable {
  case catalogUnavailable
  case notFound

  func message(catalogID: String) -> String {
    switch self {
    case .catalogUnavailable:
      "Fluke couldn't verify a public profile for \(catalogID) right now. No movement record was opened."
    case .notFound:
      "No public whale profile matches \(catalogID), so no movement record was opened."
    }
  }
}

enum MovementDestination: Equatable, Identifiable {
  case movement(Whale)
  case unavailable(catalogID: String, reason: MovementUnavailableReason)

  var id: String {
    switch self {
    case .movement(let whale): "movement:\(whale.id)"
    case .unavailable(let catalogID, _): "unavailable:\(catalogID)"
    }
  }
}

struct MovementSubmitRoute: Identifiable {
  let id = UUID()
  let submissionsEnabled: Bool
  let localIdentification: LocalIdentificationSuggestion?
}

@MainActor
@Observable
final class MovementSubmitPresentationRouter {
  var presentedRoute: MovementSubmitRoute?
  private(set) var pendingRoute: MovementSubmitRoute?

  func request(
    submissionsEnabled: Bool,
    localIdentification: LocalIdentificationSuggestion? = nil,
    movementPresented: Bool
  ) {
    let route = MovementSubmitRoute(
      submissionsEnabled: submissionsEnabled,
      localIdentification: localIdentification
    )
    if movementPresented {
      pendingRoute = route
    } else {
      presentedRoute = route
    }
  }

  func movementDidDismiss() {
    guard let pendingRoute else { return }
    self.pendingRoute = nil
    presentedRoute = pendingRoute
  }
}

@MainActor
@Observable
final class MovementNavigationModel {
  var destination: MovementDestination?

  private let repository: any WhalesRepositoryProtocol
  private var requestGeneration = 0

  init(repository: any WhalesRepositoryProtocol) {
    self.repository = repository
  }

  func present(catalogID rawCatalogID: String) async {
    requestGeneration += 1
    let generation = requestGeneration
    let catalogID = rawCatalogID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !catalogID.isEmpty else {
      destination = .unavailable(catalogID: "the selected whale", reason: .notFound)
      return
    }

    let result: BrowseResult<[Whale]>
    do {
      result = try await repository.loadCatalog()
    } catch {
      guard generation == requestGeneration else { return }
      destination = .unavailable(catalogID: catalogID, reason: .catalogUnavailable)
      return
    }
    guard generation == requestGeneration else { return }
    destination = Self.resolve(result, catalogID: catalogID)
  }

  func dismiss() {
    requestGeneration += 1
    destination = nil
  }

  private static func resolve(
    _ result: BrowseResult<[Whale]>,
    catalogID: String
  ) -> MovementDestination {
    switch result {
    case .fresh(let whales, _):
      resolved(whales, catalogID: catalogID)
    case .cached(let payload, _), .stale(let payload, _, _), .cachedOffline(let payload, _):
      resolved(payload, catalogID: catalogID)
    case .empty:
      .unavailable(catalogID: catalogID, reason: .notFound)
    case .failed:
      .unavailable(catalogID: catalogID, reason: .catalogUnavailable)
    }
  }

  private static func resolved(
    _ payload: BrowsePayload<[Whale]>,
    catalogID: String
  ) -> MovementDestination {
    switch payload {
    case .value(let whales): resolved(whales, catalogID: catalogID)
    case .empty: .unavailable(catalogID: catalogID, reason: .notFound)
    }
  }

  private static func resolved(
    _ whales: [Whale],
    catalogID: String
  ) -> MovementDestination {
    let matches = whales.filter { $0.catalogId == catalogID }
    guard matches.count == 1, let whale = matches.first else {
      let reason: MovementUnavailableReason = matches.isEmpty ? .notFound : .catalogUnavailable
      return .unavailable(catalogID: catalogID, reason: reason)
    }
    return .movement(whale)
  }
}
