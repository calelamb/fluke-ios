import FlukeKit
import FlukeReleaseB
import Foundation
import Observation

public struct QueuedLogbookEntry: Hashable, Identifiable, Sendable {
  public let id: String
  public let observedAt: Date
  public let locationName: String?

  public init(id: String, observedAt: Date, locationName: String?) {
    self.id = id
    self.observedAt = observedAt
    self.locationName = locationName
  }
}

public protocol QueuedLogbookProviding: Sendable {
  func queuedEntries() async -> [QueuedLogbookEntry]
}

public struct EmptyLogbookQueue: QueuedLogbookProviding {
  public init() {}
  public func queuedEntries() async -> [QueuedLogbookEntry] { [] }
}

public struct LogbookRow: Hashable, Identifiable, Sendable {
  public let id: String
  public let observedAt: Date
  public let locationName: String?
  public let status: LogbookStatus
}

public struct LogbookFailure: Equatable, Sendable {
  public let message: String
  public let retryable: Bool
}

@MainActor
@Observable
public final class LogbookViewModel {
  public enum SessionAction: Equatable, Sendable {
    case expire
  }

  public private(set) var rows: [LogbookRow] = []
  public private(set) var failure: LogbookFailure?
  public private(set) var isLoading = false
  public private(set) var sessionAction: SessionAction?

  private let repository: any LogbookRepositoryProtocol
  private let queue: any QueuedLogbookProviding

  public init(
    repository: any LogbookRepositoryProtocol,
    queue: any QueuedLogbookProviding
  ) {
    self.repository = repository
    self.queue = queue
  }

  public func load() async {
    isLoading = true
    failure = nil
    sessionAction = nil
    let queued = await queue.queuedEntries()
    do {
      let server = try await repository.load()
      rows = Self.mergedRows(queued: queued, server: server)
    } catch APIError.unauthorized {
      rows = Self.queuedRows(queued)
      sessionAction = .expire
    } catch {
      rows = Self.queuedRows(queued)
      failure = Self.failure(from: error)
    }
    isLoading = false
  }

  private static func mergedRows(
    queued: [QueuedLogbookEntry],
    server: [LogbookEntry]
  ) -> [LogbookRow] {
    queuedRows(queued)
      + server
      .sorted { $0.observedAt > $1.observedAt }
      .map { entry in
        LogbookRow(
          id: "server:\(entry.id)",
          observedAt: entry.observedAt,
          locationName: entry.locationName,
          status: entry.status
        )
      }
  }

  private static func queuedRows(_ entries: [QueuedLogbookEntry]) -> [LogbookRow] {
    entries
      .sorted { $0.observedAt > $1.observedAt }
      .map { entry in
        LogbookRow(
          id: "queued:\(entry.id)",
          observedAt: entry.observedAt,
          locationName: entry.locationName,
          status: .queued
        )
      }
  }

  private static func failure(from error: Error) -> LogbookFailure {
    guard let apiError = error as? APIError else {
      return LogbookFailure(
        message: "Fluke couldn't load your sightings.",
        retryable: true
      )
    }
    return LogbookFailure(
      message: apiError.errorDescription ?? "Fluke couldn't load your sightings.",
      retryable: apiError.retryable
    )
  }
}
