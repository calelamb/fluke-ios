import FlukeKit
import FlukeReleaseB
import Foundation
import Testing

@testable import FlukeFeatures

@MainActor
struct LogbookViewModelTests {
  @Test("Every logbook status has an honest explanation")
  func statusExplanations() {
    #expect(LogbookStatus.allCases.map(\.title) == ["Queued", "Pending", "Approved", "Rejected"])
    #expect(LogbookStatus.queued.explanation.contains("device"))
    #expect(LogbookStatus.pending.explanation.contains("review"))
    #expect(LogbookStatus.approved.explanation.contains("public"))
    #expect(LogbookStatus.rejected.explanation.contains("not published"))
  }

  @Test("Logbook keeps queued entries first and server entries newest first")
  func ordering() async {
    let old = Date(timeIntervalSince1970: 100)
    let new = Date(timeIntervalSince1970: 200)
    let model = LogbookViewModel(
      repository: FixtureLogbookRepository(entries: [
        .fixture(id: "approved", observedAt: new, status: .approved),
        .fixture(id: "rejected", observedAt: old, status: .rejected),
        .fixture(id: "pending", observedAt: Date(timeIntervalSince1970: 300), status: .pending),
      ]),
      queue: FixtureLogbookQueue(entries: [
        QueuedLogbookEntry(id: "queued", observedAt: old, locationName: "Puget Sound")
      ])
    )

    await model.load()

    #expect(model.rows.map(\.status) == [.queued, .pending, .approved, .rejected])
    #expect(
      model.rows.map(\.id) == [
        "queued:queued", "server:pending", "server:approved", "server:rejected",
      ])
  }

  @Test("Unauthorized logbook response asks the session to expire")
  func unauthorized() async {
    let model = LogbookViewModel(
      repository: FixtureLogbookRepository(error: APIError.unauthorized),
      queue: FixtureLogbookQueue()
    )

    await model.load()

    #expect(model.sessionAction == .expire)
    #expect(model.failure == nil)
  }

  @Test("Retryable failure preserves queued truth and exposes retry")
  func offline() async {
    let model = LogbookViewModel(
      repository: FixtureLogbookRepository(error: APIError.offline),
      queue: FixtureLogbookQueue(entries: [
        QueuedLogbookEntry(
          id: "queued",
          observedAt: Date(timeIntervalSince1970: 100),
          locationName: nil
        )
      ])
    )

    await model.load()

    #expect(model.rows.map(\.status) == [.queued])
    #expect(model.failure?.retryable == true)
    #expect(model.failure?.message == "You're offline.")
  }
}

private struct FixtureLogbookRepository: LogbookRepositoryProtocol {
  let entries: [LogbookEntry]
  let error: (any Error & Sendable)?

  init(entries: [LogbookEntry] = [], error: (any Error & Sendable)? = nil) {
    self.entries = entries
    self.error = error
  }

  func load() async throws -> [LogbookEntry] {
    if let error { throw error }
    return entries
  }
}

private struct FixtureLogbookQueue: QueuedLogbookProviding {
  let entries: [QueuedLogbookEntry]

  init(entries: [QueuedLogbookEntry] = []) {
    self.entries = entries
  }

  func queuedEntries() async -> [QueuedLogbookEntry] { entries }
}

extension LogbookEntry {
  fileprivate static func fixture(
    id: String,
    observedAt: Date,
    status: LogbookStatus
  ) -> LogbookEntry {
    LogbookEntry(
      id: id,
      observedAt: observedAt,
      locationName: nil,
      status: status
    )
  }
}
