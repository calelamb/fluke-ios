import FlukeReleaseB
import FlukeKit
import Foundation
import Testing

@testable import FlukeFeatures

@Suite("Sightings feed polling")
struct SightingsFeedPollingTests {
  @MainActor
  @Test("View model presents wire identities and provider freshness")
  func viewModelUsesRevisionedFeed() async throws {
    let json = "{\"behaviorNotes\":null,\"ecotypeGuess\":\"RESIDENT\",\"groupSize\":4,\"id\":\"internal:already-namespaced\",\"identifiedWhales\":[],\"kind\":\"internal\",\"latitude\":48.5,\"locationName\":\"Salish Sea\",\"longitude\":-123.2,\"observedAt\":\"2026-07-18T10:00:00Z\",\"photos\":[],\"revision\":1}"
    let item = try JSONDecoder.fluke.decode(SightingFeedItem.self, from: Data(json.utf8))
    let date = Date(timeIntervalSince1970: 1_721_303_200)
    let providers = FeedProvider.allCases.map {
      ProviderFreshness(expectedMaximumLag: 300, lastAttemptAt: date, lastSuccessAt: date, provider: $0, status: .succeeded)
    }
    let repository = FeedRepositoryFake(state: SightingFeedState(items: [item], tombstones: [:], syncCursor: "r1", providers: providers))
    let model = SightingsViewModel(feedRepository: repository, now: { date })

    await model.load()

    #expect(model.items.map(\.id) == ["internal:already-namespaced"])
    #expect(model.freshness == .live)
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

  @Test("Polling requires both foreground and visibility and never creates duplicate loops")
  func lifecycle() async {
    let recorder = PollRecorder(results: [.success, .success])
    let sleeps = PollSleeper()
    let poller = FeedPollingActor(
      refresh: { try await recorder.refresh() },
      sleep: { duration in try await sleeps.sleep(duration) }
    )

    await poller.setForeground(true)
    await poller.setVisible(true)
    await poller.setVisible(true)
    await eventually { await recorder.callCount == 1 }
    #expect(await poller.hasActiveLoop)

    await poller.setForeground(false)
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

    await poller.setVisible(true)
    await poller.setForeground(true)
    await eventually { await sleeps.delays.count >= 5 }
    await poller.setVisible(false)

    #expect(Array((await sleeps.delays).prefix(5)) == [.seconds(30), .seconds(60), .seconds(120), .seconds(300), .seconds(300)])
  }

  private func eventually(_ condition: @escaping @Sendable () async -> Bool) async {
    for _ in 0..<100 {
      if await condition() { return }
      await Task.yield()
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
