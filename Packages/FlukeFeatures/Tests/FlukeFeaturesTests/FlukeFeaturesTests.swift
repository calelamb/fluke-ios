import FlukeKit
import Foundation
import SwiftUI
import XCTest
@testable import FlukeFeatures

final class FlukeFeaturesVersionTests: XCTestCase {
    func test_versionIsExposed() {
        XCTAssertEqual(FlukeFeaturesVersion.current, "0.1.0")
    }
}

final class ReleaseABrowseRenderTests: XCTestCase {
    func test_shippingSurfacesInstantiate() {
        _ = SightingsView(repository: EmptySightingsRepository())
        _ = WhalesView(repository: EmptyWhalesRepository())
        _ = LearnView()
        _ = AtlasView(
            historicalRepository: EmptyHistoricalRepository(),
            predictionRepository: EmptyPredictionRepository(),
            whalesRepository: EmptyWhalesRepository()
        )
    }
}

private actor EmptyHistoricalRepository: HistoricalSightingsRepositoryProtocol {
    private let metadata = BrowseMetadata(fetchedAt: Date(), schemaVersion: 1)

    func load(from: Date, to: Date, pod: Pod?) async throws -> BrowseResult<[HistoricalSighting]> {
        .empty(metadata: metadata)
    }
}

private actor EmptyPredictionRepository: PredictionRepositoryProtocol {
    private let metadata = BrowseMetadata(fetchedAt: Date(), schemaVersion: 1)

    func load(
        subject: PredictionRepository.Subject,
        horizon: PredictionHorizon
    ) async throws -> BrowseResult<Prediction?> {
        .empty(metadata: metadata)
    }
}

private actor EmptyWhalesRepository: WhalesRepositoryProtocol {
    private let metadata = BrowseMetadata(fetchedAt: Date(), schemaVersion: 1)

    func loadCatalog() async throws -> BrowseResult<[Whale]> {
        .empty(metadata: metadata)
    }

    func loadProfile(id: String) async throws -> BrowseResult<WhaleProfile?> {
        .empty(metadata: metadata)
    }

    func loadTrack(
        whaleId: String,
        from: Date,
        to: Date
    ) async throws -> BrowseResult<[MovementTrackPoint]> {
        .empty(metadata: metadata)
    }
}

private actor EmptySightingsRepository: SightingsRepositoryProtocol {
    private let metadata = BrowseMetadata(fetchedAt: Date(), schemaVersion: 1)

    func loadApproved() async throws -> BrowseResult<[Sighting]> {
        .empty(metadata: metadata)
    }

    func loadExternal(source: String?, sinceDays: Int) async throws -> BrowseResult<[ExternalSighting]> {
        .empty(metadata: metadata)
    }
}
