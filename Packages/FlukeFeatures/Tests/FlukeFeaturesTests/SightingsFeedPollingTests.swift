import FlukeKit
import FlukeReleaseB
import Foundation
import Testing

@testable import FlukeFeatures

@Suite("Sightings feed polling")
struct SightingsFeedPollingTests {
  @MainActor
  @Test("View model presents wire identities and provider freshness")
  func viewModelUsesRevisionedFeed() async throws {
    let json =
      "{\"behaviorNotes\":null,\"ecotypeGuess\":\"RESIDENT\",\"groupSize\":4,\"id\":\"internal:already-namespaced\",\"identifiedWhales\":[],\"kind\":\"internal\",\"latitude\":48.5,\"locationName\":\"Salish Sea\",\"longitude\":-123.2,\"observedAt\":\"2026-07-18T10:00:00Z\",\"photos\":[],\"revision\":1}"
    let item = try JSONDecoder.fluke.decode(SightingFeedItem.self, from: Data(json.utf8))
    let date = Date(timeIntervalSince1970: 1_721_303_200)
    let providers = FeedProvider.allCases.map {
      ProviderFreshness(
        expectedMaximumLag: 300, lastAttemptAt: date, lastSuccessAt: date, provider: $0,
        status: .succeeded)
    }
    let repository = FeedRepositoryFake(
      state: SightingFeedState(
        items: [item], tombstones: [:], syncCursor: "r1", providers: providers))
    let model = SightingsViewModel(feedRepository: repository, now: { date })

    await model.load()

    #expect(model.items.map(\.id) == ["internal:already-namespaced"])
    #expect(model.freshness == .live)
  }

  @MainActor
  @Test("Freshness ages from the clock and expires through refresh failures")
  func freshnessAdvancesThroughFailure() async throws {
    let clock = LockedNow(Date(timeIntervalSince1970: 1_721_303_200))
    let providers = FeedProvider.allCases.map {
      ProviderFreshness(
        expectedMaximumLag: 300, lastAttemptAt: clock.value,
        lastSuccessAt: clock.value, provider: $0, status: .succeeded
      )
    }
    let repository = LoadThenFailFeedRepository(
      state: SightingFeedState(
        items: [], tombstones: [:], syncCursor: "r1", providers: providers
      )
    )
    let model = SightingsViewModel(feedRepository: repository, now: { clock.value })

    await model.load()
    #expect(model.freshness == .live)
    clock.advance(by: 601)
    #expect(model.freshness == .recent(lastSuccessAge: 601))
    await #expect(throws: PollFailure.self) { try await model.pollRefresh() }
    clock.advance(by: 60)
    #expect(model.freshness == .recent(lastSuccessAge: 661))
  }

  @MainActor
  @Test("Older feed pages append without blocking initial content")
  func loadsOlderFeedPage() async throws {
    let first = try feedItem(id: "external:acartia:new", revision: 2, hour: 12)
    let older = try feedItem(id: "external:gbif:older", revision: 1, hour: 10)
    let initial = SightingFeedState(
      items: [first], tombstones: [:], syncCursor: "r2", providers: feedProviders())
    let complete = SightingFeedState(
      items: [first, older], tombstones: [:], syncCursor: "r2", providers: feedProviders())
    let repository = PagingFeedRepository(initial: initial, complete: complete)
    let model = SightingsViewModel(feedRepository: repository)

    await model.load()
    #expect(model.items.map(\.id) == ["external:acartia:new"])
    #expect(model.hasMoreHistory)

    await model.loadMore()

    #expect(model.items.map(\.id) == ["external:acartia:new", "external:gbif:older"])
    #expect(!model.hasMoreHistory)
    #expect(await repository.loadMoreCallCount == 1)
  }

  @MainActor
  @Test("View-model polling propagates failure so the poller can back off")
  func viewModelPropagatesPollingFailure() async {
    let model = SightingsViewModel(feedRepository: FailingFeedRepositoryFake())
    var didThrow = false

    do { try await model.pollRefresh() } catch { didThrow = true }

    #expect(didThrow)
    #expect(model.primaryFailure?.code == "SIGHTING_FEED_FAILED")
  }

  @MainActor
  @Test("Lifecycle cancellation does not present a refresh failure")
  func cancellationDoesNotBecomeFailure() async {
    let repository = BlockingFeedRepository()
    let model = SightingsViewModel(feedRepository: repository)
    let refresh = Task { try await model.pollRefresh() }
    await eventually { await repository.refreshStarted }

    refresh.cancel()
    await #expect(throws: CancellationError.self) { try await refresh.value }

    #expect(model.primaryFailure == nil)
  }

  @Test("Polling requires both foreground and visibility and never creates duplicate loops")
  func lifecycle() async {
    let recorder = PollRecorder(results: [.success, .success])
    let sleeps = PollSleeper()
    let poller = FeedPollingActor(
      refresh: { try await recorder.refresh() },
      sleep: { duration in try await sleeps.sleep(duration) }
    )

    await poller.setLifecycle(visible: true, foreground: true)
    await poller.setLifecycle(visible: true, foreground: true)
    await eventually { await recorder.callCount == 1 }
    #expect(await poller.hasActiveLoop)

    await poller.setLifecycle(visible: true, foreground: false)
    #expect(!(await poller.hasActiveLoop))
  }

  @Test("Failures use capped 30, 60, 120, 300 second backoff")
  func backoff() async {
    let recorder = PollRecorder(results: [.failure, .failure, .failure, .failure, .failure])
    let sleeps = PollSleeper(autoResume: true)
    let poller = FeedPollingActor(
      refresh: { try await recorder.refresh() },
      sleep: { duration in try await sleeps.sleep(duration) }
    )

    await poller.setLifecycle(visible: true, foreground: true)
    await eventually { await sleeps.delays.count >= 5 }
    await poller.setLifecycle(visible: false, foreground: true)

    #expect(
      Array((await sleeps.delays).prefix(5)) == [
        .seconds(30), .seconds(60), .seconds(120), .seconds(300), .seconds(300),
      ])
  }

  @Test("Rapid tab and scene transitions cancel a mid-refresh loop in order")
  func rapidLifecycleTransitions() async {
    let refresh = BlockingRefresh()
    let poller = FeedPollingActor(refresh: { try await refresh.run() })

    await poller.setLifecycle(visible: true, foreground: true)
    await eventually { await refresh.startCount == 1 }
    await poller.setLifecycle(visible: false, foreground: true)
    await eventually { await refresh.cancellationCount == 1 }
    await poller.setLifecycle(visible: true, foreground: false)
    #expect(!(await poller.hasActiveLoop))
    await poller.setLifecycle(visible: true, foreground: true)
    await eventually { await refresh.startCount == 2 }
    await poller.setLifecycle(visible: true, foreground: false)
    await eventually { await refresh.cancellationCount == 2 }

    #expect(!(await poller.hasActiveLoop))
    #expect(await refresh.maximumConcurrentCount == 1)
  }

  @Test("A superseded structured lifecycle cannot deactivate its replacement")
  func staleLifecycleCleanupIsIgnored() async throws {
    let refresh = BlockingRefresh()
    let poller = FeedPollingActor(refresh: { try await refresh.run() })
    let first = Task {
      await poller.maintainLifecycle(visible: true, foreground: true)
    }
    await eventually { await refresh.startCount == 1 }
    let replacement = Task {
      await poller.maintainLifecycle(visible: true, foreground: true)
    }
    try await Task.sleep(for: .milliseconds(10))

    first.cancel()
    await first.value
    #expect(await poller.hasActiveLoop)

    replacement.cancel()
    await replacement.value
    await eventually { !(await poller.hasActiveLoop) }
    #expect(!(await poller.hasActiveLoop))
  }

  private func eventually(_ condition: @escaping @Sendable () async -> Bool) async {
    for _ in 0..<100 {
      if await condition() { return }
      await Task.yield()
    }
  }

  private func feedItem(id: String, revision: Int, hour: Int) throws -> SightingFeedItem {
    let json = """
      {"attribution":"Real provider","ecotypeGuess":null,"groupSize":3,"id":"\(id)","kind":"external","latitude":48.4,"longitude":-123.1,"notes":null,"observedAt":"2026-07-18T\(hour):00:00Z","revision":\(revision),"source":"provider","sourceUrl":"https://example.test/record","species":"Orcinus orca","trusted":true}
      """
    return try JSONDecoder.fluke.decode(SightingFeedItem.self, from: Data(json.utf8))
  }

  private func feedProviders() -> [ProviderFreshness] {
    FeedProvider.allCases.map {
      ProviderFreshness(
        expectedMaximumLag: 300, lastAttemptAt: nil, lastSuccessAt: nil,
        provider: $0, status: .succeeded)
    }
  }
}

private actor PollRecorder {
  enum Result { case success, failure }
  private var results: [Result]
  private(set) var callCount = 0

  init(results: [Result]) { self.results = results }

  func refresh() throws {
    callCount += 1
    guard !results.isEmpty else { return }
    if results.removeFirst() == .failure { throw PollFailure.expected }
  }
}

private actor PollSleeper {
  private(set) var delays: [Duration] = []
  private let autoResume: Bool

  init(autoResume: Bool = false) { self.autoResume = autoResume }

  func sleep(_ duration: Duration) async throws {
    delays.append(duration)
    if autoResume { return }
    try await Task.sleep(for: .seconds(60))
  }
}

private enum PollFailure: Error { case expected }

private final class LockedNow: @unchecked Sendable {
  private let lock = NSLock()
  private var date: Date

  init(_ date: Date) { self.date = date }

  var value: Date {
    lock.withLock { date }
  }

  func advance(by interval: TimeInterval) {
    lock.withLock { date = date.addingTimeInterval(interval) }
  }
}

private actor BlockingRefresh {
  private(set) var startCount = 0
  private(set) var cancellationCount = 0
  private(set) var maximumConcurrentCount = 0
  private var concurrentCount = 0

  func run() async throws {
    startCount += 1
    concurrentCount += 1
    maximumConcurrentCount = max(maximumConcurrentCount, concurrentCount)
    do {
      try await Task.sleep(for: .seconds(60))
      concurrentCount -= 1
    } catch {
      concurrentCount -= 1
      cancellationCount += 1
      throw error
    }
  }
}

private actor FeedRepositoryFake: SightingFeedRepositoryProtocol {
  let state: SightingFeedState
  init(state: SightingFeedState) { self.state = state }
  func load() async throws -> SightingFeedState { state }
  func refresh() async throws -> SightingFeedState { state }
}

private actor FailingFeedRepositoryFake: SightingFeedRepositoryProtocol {
  func load() async throws -> SightingFeedState { throw PollFailure.expected }
  func refresh() async throws -> SightingFeedState { throw PollFailure.expected }
}

private actor LoadThenFailFeedRepository: SightingFeedRepositoryProtocol {
  let state: SightingFeedState
  init(state: SightingFeedState) { self.state = state }
  func load() async throws -> SightingFeedState { state }
  func refresh() async throws -> SightingFeedState { throw PollFailure.expected }
}

private actor BlockingFeedRepository: SightingFeedRepositoryProtocol {
  private(set) var refreshStarted = false

  func load() async throws -> SightingFeedState { throw PollFailure.expected }

  func refresh() async throws -> SightingFeedState {
    refreshStarted = true
    try await Task.sleep(for: .seconds(60))
    throw PollFailure.expected
  }
}

private actor PagingFeedRepository: SightingFeedRepositoryProtocol {
  let initial: SightingFeedState
  let complete: SightingFeedState
  private(set) var loadMoreCallCount = 0
  private var more = true

  init(initial: SightingFeedState, complete: SightingFeedState) {
    self.initial = initial
    self.complete = complete
  }

  func hasMoreHistory() async -> Bool { more }
  func load() async throws -> SightingFeedState { initial }
  func refresh() async throws -> SightingFeedState { initial }

  func loadMore() async throws -> SightingFeedState {
    loadMoreCallCount += 1
    more = false
    return complete
  }
}
