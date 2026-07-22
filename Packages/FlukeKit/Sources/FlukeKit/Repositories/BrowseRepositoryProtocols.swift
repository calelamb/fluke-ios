import Foundation

public protocol SightingsRepositoryProtocol: Sendable {
    func loadApproved() async throws -> BrowseResult<[Sighting]>
    func loadExternal(source: String?, sinceDays: Int) async throws -> BrowseResult<[ExternalSighting]>
}

public protocol WhalesRepositoryProtocol: Sendable {
    func catalogUpdates() -> AsyncThrowingStream<BrowseResult<[Whale]>, Error>
    func loadCatalog() async throws -> BrowseResult<[Whale]>
    func loadProfile(id: String) async throws -> BrowseResult<WhaleProfile?>
    func loadTrack(whaleId: String, from: Date, to: Date) async throws -> BrowseResult<[MovementTrackPoint]>
}

extension WhalesRepositoryProtocol {
    public func catalogUpdates() -> AsyncThrowingStream<BrowseResult<[Whale]>, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(try await loadCatalog())
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

public protocol HistoricalSightingsRepositoryProtocol: Sendable {
    func load(from: Date, to: Date, pod: Pod?) async throws -> BrowseResult<[HistoricalSighting]>
}

public protocol PredictionRepositoryProtocol: Sendable {
    func load(
        subject: PredictionRepository.Subject,
        horizon: PredictionHorizon
    ) async throws -> BrowseResult<Prediction?>
}
