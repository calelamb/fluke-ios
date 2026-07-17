import FlukeKit
import Foundation
import Testing

@testable import Fluke

@MainActor
struct MovementNavigationModelTests {
  @Test("A sighting catalog ID resolves to the repository whale before movement opens")
  func resolvesCatalogID() async {
    let whale = makeWhale(id: "whale-record-35", catalogID: "J35")
    let model = MovementNavigationModel(
      repository: MovementRepository(catalogResult: .fresh(value: [whale], metadata: metadata))
    )

    await model.present(catalogID: "J35")

    #expect(model.destination == .movement(whale))
  }

  @Test("An unknown sighting catalog ID fails closed without inventing a whale")
  func rejectsUnknownCatalogID() async {
    let model = MovementNavigationModel(
      repository: MovementRepository(catalogResult: .fresh(value: [], metadata: metadata))
    )

    await model.present(catalogID: "J404")

    #expect(model.destination == .unavailable(catalogID: "J404", reason: .notFound))
  }

  @Test("A catalog outage fails closed with a truthful unavailable route")
  func rejectsUnavailableCatalog() async {
    let failure = BrowseFailure(
      code: "OFFLINE",
      message: "Network unavailable",
      retryable: true,
      requestId: nil
    )
    let model = MovementNavigationModel(
      repository: MovementRepository(catalogResult: .failed(failure))
    )

    await model.present(catalogID: "J35")

    #expect(model.destination == .unavailable(catalogID: "J35", reason: .catalogUnavailable))
  }

  @Test("A thrown catalog request also fails closed")
  func rejectsThrownCatalogRequest() async {
    let model = MovementNavigationModel(
      repository: MovementRepository(
        catalogResult: .empty(metadata: metadata),
        throwsCatalog: true
      )
    )

    await model.present(catalogID: "J35")

    #expect(model.destination == .unavailable(catalogID: "J35", reason: .catalogUnavailable))
  }

  @Test("Blank catalog identity cannot open movement")
  func rejectsBlankCatalogID() async {
    let model = MovementNavigationModel(
      repository: MovementRepository(catalogResult: .fresh(value: [], metadata: metadata))
    )

    await model.present(catalogID: "  \n")

    #expect(
      model.destination == .unavailable(catalogID: "the selected whale", reason: .notFound)
    )
  }

  @Test("Cached catalog truth can resolve movement while offline")
  func resolvesCachedCatalog() async {
    let whale = makeWhale(id: "whale-record-35", catalogID: "J35")
    let model = MovementNavigationModel(
      repository: MovementRepository(
        catalogResult: .cachedOffline(payload: .value([whale]), metadata: metadata)
      )
    )

    await model.present(catalogID: "J35")

    #expect(model.destination == .movement(whale))
  }

  @Test("Dismissing movement clears the destination")
  func dismissesDestination() async {
    let whale = makeWhale(id: "whale-record-35", catalogID: "J35")
    let model = MovementNavigationModel(
      repository: MovementRepository(catalogResult: .fresh(value: [whale], metadata: metadata))
    )
    await model.present(catalogID: "J35")

    model.dismiss()

    #expect(model.destination == nil)
  }

  @Test("Movement submit preserves the server capability while routing to the sheet")
  func preservesSubmissionCapability() async {
    let whale = makeWhale(id: "whale-record-35", catalogID: "J35")
    let model = MovementNavigationModel(
      repository: MovementRepository(catalogResult: .fresh(value: [whale], metadata: metadata))
    )
    await model.present(catalogID: "J35")

    let route = model.routeToSubmit(submissionsEnabled: false)

    #expect(route.submissionsEnabled == false)
    #expect(model.destination == nil)
  }

  @Test("Unavailable movement copy distinguishes missing truth from a catalog outage")
  func unavailableCopy() {
    #expect(
      MovementUnavailableReason.notFound.message(catalogID: "J35")
        == "No public whale profile matches J35, so no movement record was opened."
    )
    #expect(
      MovementUnavailableReason.catalogUnavailable.message(catalogID: "J35")
        == "Fluke couldn't verify a public profile for J35 right now. No movement record was opened."
    )
  }

  private var metadata: BrowseMetadata {
    BrowseMetadata(fetchedAt: Date(timeIntervalSince1970: 1_700_000_000), schemaVersion: 1)
  }

  private func makeWhale(id: String, catalogID: String) -> Whale {
    Whale(
      id: id,
      catalogId: catalogID,
      name: "Tahlequah",
      ecotype: .resident,
      pod: "J",
      sex: .female,
      birthYear: 1998,
      deathYear: nil,
      status: .alive,
      biography: nil,
      distinguishingMarks: nil,
      heroImageUrl: nil,
      notableEvents: [],
      sourceCitations: []
    )
  }
}

private actor MovementRepository: WhalesRepositoryProtocol {
  let catalogResult: BrowseResult<[Whale]>
  let throwsCatalog: Bool

  init(catalogResult: BrowseResult<[Whale]>, throwsCatalog: Bool = false) {
    self.catalogResult = catalogResult
    self.throwsCatalog = throwsCatalog
  }

  func loadCatalog() async throws -> BrowseResult<[Whale]> {
    if throwsCatalog { throw MovementRepositoryError.unavailable }
    return catalogResult
  }

  func loadProfile(id: String) async throws -> BrowseResult<WhaleProfile?> {
    .empty(metadata: BrowseMetadata(fetchedAt: .distantPast, schemaVersion: 1))
  }

  func loadTrack(
    whaleId: String,
    from: Date,
    to: Date
  ) async throws -> BrowseResult<[MovementTrackPoint]> {
    .empty(metadata: BrowseMetadata(fetchedAt: .distantPast, schemaVersion: 1))
  }
}

private enum MovementRepositoryError: Error {
  case unavailable
}
