import FlukeKit
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

  func routeToSubmit(submissionsEnabled: Bool) -> MovementSubmitRoute {
    dismiss()
    return MovementSubmitRoute(submissionsEnabled: submissionsEnabled)
  }

  private static func resolve(
    _ result: BrowseResult<[Whale]>,
    catalogID: String
  ) -> MovementDestination {
    switch result {
    case .fresh(let whales, _):
      resolved(whales, catalogID: catalogID)
    case .stale(let payload, _, _), .cachedOffline(let payload, _):
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
    guard let whale = whales.first(where: { $0.catalogId == catalogID }) else {
      return .unavailable(catalogID: catalogID, reason: .notFound)
    }
    return .movement(whale)
  }
}
