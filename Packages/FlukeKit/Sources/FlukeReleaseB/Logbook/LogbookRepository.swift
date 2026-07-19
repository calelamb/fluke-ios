import FlukeKit
import Foundation

public protocol LogbookRepositoryProtocol: Sendable {
  func load() async throws -> [LogbookEntry]
}

public struct LogbookRepository: LogbookRepositoryProtocol, Sendable {
  private let api: APIClient

  public init(api: APIClient) {
    self.api = api
  }

  public func load() async throws -> [LogbookEntry] {
    let response: PaginatedResponse<OwnerSighting> = try await api.get(
      APIRequest(path: ReleaseBEndpoint.mySightings)
    )
    return response.items.map(\.logbookEntry)
  }
}

private struct OwnerSighting: Codable, Hashable, Sendable {
  let behaviorNotes: String?
  let createdAt: Date
  let ecotypeGuess: Ecotype?
  let groupSize: Int?
  let id: String
  let latitude: Double
  let locationName: String?
  let longitude: Double
  let observedAt: Date
  let photoCount: Int
  let rejectionReason: String?
  let status: SightingStatus

  var logbookEntry: LogbookEntry {
    LogbookEntry(
      id: id,
      observedAt: observedAt,
      locationName: locationName,
      status: logbookStatus,
      createdAt: createdAt,
      photoCount: photoCount,
      rejectionReason: rejectionReason
    )
  }

  private var logbookStatus: LogbookStatus {
    switch status {
    case .pending: .pending
    case .approved: .approved
    case .rejected: .rejected
    }
  }
}
