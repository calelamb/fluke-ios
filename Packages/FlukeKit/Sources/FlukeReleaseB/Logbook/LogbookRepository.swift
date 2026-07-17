import FlukeKit

public protocol LogbookRepositoryProtocol: Sendable {
  func load() async throws -> [LogbookEntry]
}

public struct LogbookRepository: LogbookRepositoryProtocol, Sendable {
  private let api: APIClient

  public init(api: APIClient) {
    self.api = api
  }

  public func load() async throws -> [LogbookEntry] {
    let response: PaginatedResponse<Sighting> = try await api.get(
      APIRequest(path: ReleaseBEndpoint.mySightings)
    )
    return response.items.map(LogbookEntry.init(sighting:))
  }
}
