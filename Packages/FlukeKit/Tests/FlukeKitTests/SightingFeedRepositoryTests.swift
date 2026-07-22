import Foundation
import Testing

@testable import FlukeKit
@testable import FlukeReleaseB

@Suite("Revisioned sighting feed")
struct SightingFeedRepositoryTests {
  @Test("Strict union rejects unknown and missing keys")
  func strictUnion() throws {
    let valid = internalJSON(id: "internal:one", revision: 1)
    _ = try JSONDecoder.fluke.decode(SightingFeedItem.self, from: Data(valid.utf8))

    let unknown = valid.replacingOccurrences(
      of: "\"revision\":1", with: "\"revision\":1,\"extra\":true")
    #expect(throws: DecodingError.self) {
      try JSONDecoder.fluke.decode(SightingFeedItem.self, from: Data(unknown.utf8))
    }
    let missing = valid.replacingOccurrences(of: "\"photos\":[],", with: "")
    #expect(throws: DecodingError.self) {
      try JSONDecoder.fluke.decode(SightingFeedItem.self, from: Data(missing.utf8))
    }
  }

  @Test("Nested values and public bounds are validated")
  func validatesBounds() throws {
    let badCoordinate = internalJSON(id: "internal:one", revision: 1)
      .replacingOccurrences(of: "\"latitude\":48.5", with: "\"latitude\":91")
    #expect(throws: DecodingError.self) {
      try JSONDecoder.fluke.decode(SightingFeedItem.self, from: Data(badCoordinate.utf8))
    }

    let badPhoto = internalJSON(id: "internal:one", revision: 1)
      .replacingOccurrences(
        of: "\"photos\":[]",
        with:
          "\"photos\":[{\"id\":\"p1\",\"url\":\"file:///private\",\"thumbnailUrl\":\"https://example.test/t.jpg\",\"orderIndex\":0}]"
      )
    #expect(throws: DecodingError.self) {
      try JSONDecoder.fluke.decode(SightingFeedItem.self, from: Data(badPhoto.utf8))
    }

    let badPhotoOrder = internalJSON(id: "internal:one", revision: 1)
      .replacingOccurrences(
        of: "\"photos\":[]",
        with:
          "\"photos\":[{\"id\":\"p1\",\"url\":\"https://example.test/p.jpg\",\"thumbnailUrl\":\"https://example.test/t.jpg\",\"orderIndex\":-1}]"
      )
    #expect(throws: DecodingError.self) {
      try JSONDecoder.fluke.decode(SightingFeedItem.self, from: Data(badPhotoOrder.utf8))
    }

    let badEcotype = internalJSON(id: "internal:one", revision: 1)
      .replacingOccurrences(of: "\"RESIDENT\"", with: "\"NEW_SERVER_VALUE\"")
    #expect(throws: DecodingError.self) {
      try JSONDecoder.fluke.decode(SightingFeedItem.self, from: Data(badEcotype.utf8))
    }
  }

  @Test("Only greater revisions apply and tombstone revisions remain")
  func immutableRevisionMerge() throws {
    let first = try decodeItem(
      internalJSON(id: "internal:one", revision: 4, observedAt: "2026-07-18T11:00:00Z"))
    let tie = try decodeItem(
      internalJSON(id: "internal:two", revision: 2, observedAt: "2026-07-18T11:00:00Z"))
    let initial = SightingFeedState(
      items: [tie, first], tombstones: [:], syncCursor: "r4", providers: [])
    let removed = try decodeItem("{\"id\":\"internal:one\",\"kind\":\"removed\",\"revision\":5}")
    let stale = try decodeItem(internalJSON(id: "internal:one", revision: 4))

    let merged = initial.applying(items: [removed, stale], syncCursor: "r5", providers: [])

    #expect(initial.items.map(\.id) == ["internal:one", "internal:two"])
    #expect(merged.items.map(\.id) == ["internal:two"])
    #expect(merged.tombstones["internal:one"] == 5)
  }

  @Test("Duplicate IDs cannot trap or duplicate presentation")
  func duplicateIDsAreSafelyCollapsed() throws {
    let old = try decodeItem(internalJSON(id: "internal:duplicate", revision: 1))
    let new = try decodeItem(internalJSON(id: "internal:duplicate", revision: 2))

    let state = SightingFeedState(
      items: [old, new], tombstones: [:], syncCursor: "r2", providers: [])

    #expect(state.items.count == 1)
    #expect(state.items.first?.revision == 2)
  }

  @Test("Retained state remains bounded and pruned tombstones cannot resurrect")
  func boundedRetainedState() throws {
    let firstPoll = try (1...10_000).map { revision in
      try decodeItem(
        "{\"id\":\"removed:\(revision)\",\"kind\":\"removed\",\"revision\":\(revision)}")
    }
    let secondPoll = try (10_001...20_000).map { revision in
      try decodeItem(
        "{\"id\":\"removed:\(revision)\",\"kind\":\"removed\",\"revision\":\(revision)}")
    }
    let initial = SightingFeedState(
      items: [], tombstones: [:], revisionFloor: 0,
      syncCursor: "r0", providers: providers()
    )

    let bounded =
      initial
      .applying(items: firstPoll, syncCursor: "r10000", providers: providers())
      .applying(items: secondPoll, syncCursor: "r20000", providers: providers())
    let stale = try decodeItem(internalJSON(id: "removed:1", revision: 1))
    let afterStale = bounded.applying(items: [stale], syncCursor: "r20000", providers: providers())

    #expect(bounded.items.count + bounded.tombstones.count <= 10_000)
    #expect(bounded.revisionFloor >= 10_000)
    #expect(!afterStale.items.contains { $0.id == "removed:1" })
  }

  @Test("Wire IDs remain unchanged and ordering is observedAt descending then ID")
  func stableOrderAndIdentity() throws {
    let laterB = try decodeItem(
      externalJSON(id: "external:CWR:b", revision: 2, observedAt: "2026-07-18T12:00:00Z"))
    let laterA = try decodeItem(
      internalJSON(id: "internal:a", revision: 1, observedAt: "2026-07-18T12:00:00Z"))
    let earlier = try decodeItem(
      internalJSON(id: "internal:z", revision: 3, observedAt: "2026-07-18T10:00:00Z"))
    let state = SightingFeedState(
      items: [earlier, laterB, laterA], tombstones: [:], syncCursor: "r3", providers: [])

    #expect(state.items.map(\.id) == ["external:CWR:b", "internal:a", "internal:z"])
  }

  @Test("Page decoder requires exact keys, two unique providers, and cursor semantics")
  func strictPage() throws {
    let page = pageJSON(items: [], hasMore: false, pageCursor: nil, syncCursor: "r1")
    _ = try JSONDecoder.fluke.decode(SightingFeedPage.self, from: Data(page.utf8))
    let extra = page.replacingOccurrences(
      of: "\"hasMore\":false", with: "\"hasMore\":false,\"extra\":0")
    #expect(throws: DecodingError.self) {
      try JSONDecoder.fluke.decode(SightingFeedPage.self, from: Data(extra.utf8))
    }
  }

  @Test("Freshness is live only when both providers are within their advertised lag")
  func providerFreshness() throws {
    let now = Date(timeIntervalSince1970: 1_721_303_200)
    let recent = now.addingTimeInterval(-60)
    let providers = [
      ProviderFreshness(
        expectedMaximumLag: 300, lastAttemptAt: recent, lastSuccessAt: recent, provider: .acartia,
        status: .succeeded),
      ProviderFreshness(
        expectedMaximumLag: 300, lastAttemptAt: recent, lastSuccessAt: recent, provider: .gbif,
        status: .failed),
    ]
    #expect(SightingFeedFreshness(providers: providers, now: now) == .live)
    #expect(
      SightingFeedFreshness(providers: Array(providers.dropLast()), now: now)
        == .recent(lastSuccessAge: 60))
  }

  @Test("Initial history returns one page and older sightings load on demand")
  func pagesHistoryOnDemand() async throws {
    let transport = FeedTransport(responses: [
      .json(
        pageJSON(
          items: [internalJSON(id: "internal:a", revision: 1)], hasMore: true, pageCursor: "page-2",
          syncCursor: "sync-1"), etag: "\"first\""),
      .json(
        pageJSON(
          items: [internalJSON(id: "internal:b", revision: 2)], hasMore: false, pageCursor: nil,
          syncCursor: "sync-1"), etag: "\"second\""),
    ])
    let repository = SightingFeedRepository(api: api(transport), cache: MemoryBrowseCacheStore())

    let initial = try await repository.load()

    #expect(initial.items.map(\.id) == ["internal:a"])
    #expect(await transport.requests.count == 1)
    #expect(await repository.hasMoreHistory())

    let complete = try await repository.loadMore()
    let requests = await transport.requests

    #expect(complete.items.map(\.id) == ["internal:a", "internal:b"])
    #expect(requests.count == 2)
    #expect(requests[0].url?.query?.contains("pageCursor") == false)
    #expect(requests[0].url?.query?.contains("syncCursor") == false)
    #expect(requests[1].url?.query?.contains("pageCursor=page-2") == true)
    #expect(requests[1].url?.query?.contains("syncCursor") == false)
    #expect(!(await repository.hasMoreHistory()))
  }

  @Test("Cached feed is emitted before the initial network page completes")
  func cachedFeedEmitsFirst() async throws {
    let cache = MemoryBrowseCacheStore()
    let cachedItem = try decodeItem(internalJSON(id: "internal:cached", revision: 1))
    let cached = SightingFeedState(
      items: [cachedItem], tombstones: [:], syncCursor: "sync-cached", providers: providers())
    try await cache.replace(
      BrowseCacheDocument(resource: "sighting-feed", fetchedAt: Date(), payload: .value(cached)),
      for: BrowseCacheKey(resource: "sighting-feed", identity: "global")
    )
    let transport = CancellableFeedTransport()
    let repository = SightingFeedRepository(api: api(transport), cache: cache)
    var updates = repository.updates().makeAsyncIterator()

    let first = try await updates.next()
    #expect(first?.items.map(\.id) == ["internal:cached"])
    await eventually { await transport.isWaiting }

    await transport.succeed(pageJSON(
      items: [internalJSON(id: "internal:fresh", revision: 2)],
      hasMore: false, pageCursor: nil, syncCursor: "sync-fresh"))
    let second = try await updates.next()

    #expect(second?.items.map(\.id) == ["internal:fresh"])
  }

  @Test("Concurrent older-page requests coalesce into one transport")
  func coalescesLoadMore() async throws {
    let transport = FeedTransport(
      responses: [
        .json(pageJSON(
          items: [internalJSON(id: "internal:new", revision: 2)],
          hasMore: true, pageCursor: "page-2", syncCursor: "sync-2"), etag: nil),
        .json(pageJSON(
          items: [internalJSON(id: "internal:old", revision: 1)],
          hasMore: false, pageCursor: nil, syncCursor: "sync-2"), etag: nil),
      ],
      delay: .milliseconds(30)
    )
    let repository = SightingFeedRepository(api: api(transport), cache: MemoryBrowseCacheStore())
    _ = try await repository.load()

    async let first = repository.loadMore()
    async let second = repository.loadMore()
    _ = try await (first, second)

    #expect(await transport.requests.count == 2)
    #expect(try await repository.load().items.count == 2)
  }

  @Test("Sync drains returned sync cursors, never page cursors, and applies tombstones")
  func drainsSync() async throws {
    let transport = FeedTransport(responses: [
      .json(
        pageJSON(
          items: [internalJSON(id: "internal:a", revision: 1)], hasMore: false, pageCursor: nil,
          syncCursor: "sync-1"), etag: nil),
      .json(
        syncPageJSON(
          items: [internalJSON(id: "internal:a", revision: 2)], hasMore: true, syncCursor: "sync-2"),
        etag: nil),
      .json(
        syncPageJSON(
          items: ["{\"id\":\"internal:a\",\"kind\":\"removed\",\"revision\":3}"], hasMore: false,
          syncCursor: "sync-3"), etag: nil),
    ])
    let repository = SightingFeedRepository(api: api(transport), cache: MemoryBrowseCacheStore())
    _ = try await repository.load()

    let state = try await repository.refresh()
    let requests = await transport.requests

    #expect(state.items.isEmpty)
    #expect(state.tombstones["internal:a"] == 3)
    #expect(requests[1].url?.query?.contains("syncCursor=sync-1") == true)
    #expect(requests[2].url?.query?.contains("syncCursor=sync-2") == true)
    #expect(requests.dropFirst().allSatisfy { $0.url?.query?.contains("pageCursor") == false })
  }

  @Test("Conditional requests keep ETags cursor-specific and reuse exact 304 representations")
  func cursorSpecificETags() async throws {
    let transport = FeedTransport(responses: [
      .json(
        pageJSON(items: [], hasMore: false, pageCursor: nil, syncCursor: "sync-1"),
        etag: "\"history\""),
      .json(syncPageJSON(items: [], hasMore: false, syncCursor: "sync-1"), etag: "\"sync\""),
      .notModified(etag: "\"sync\""),
    ])
    let repository = SightingFeedRepository(api: api(transport), cache: MemoryBrowseCacheStore())
    _ = try await repository.load()
    _ = try await repository.refresh()
    _ = try await repository.refresh()
    let requests = await transport.requests

    #expect(requests[1].value(forHTTPHeaderField: "If-None-Match") == nil)
    #expect(requests[2].value(forHTTPHeaderField: "If-None-Match") == "\"sync\"")
  }

  @Test("A 304 replacement ETag is retained for the reusable cursor")
  func retainsReplacementETag() async throws {
    let transport = FeedTransport(responses: [
      .json(pageJSON(items: [], hasMore: false, pageCursor: nil, syncCursor: "sync-1"), etag: nil),
      .json(syncPageJSON(items: [], hasMore: false, syncCursor: "sync-1"), etag: "\"old\""),
      .notModified(etag: "\"replacement\""),
      .notModified(etag: "\"replacement\""),
    ])
    let repository = SightingFeedRepository(api: api(transport), cache: MemoryBrowseCacheStore())
    _ = try await repository.load()
    _ = try await repository.refresh()
    _ = try await repository.refresh()
    _ = try await repository.refresh()

    #expect(
      await transport.requests.last?.value(forHTTPHeaderField: "If-None-Match") == "\"replacement\""
    )
  }

  @Test("Malformed sync and history semantics fail closed")
  func rejectsMalformedPageSemantics() async throws {
    let historyTombstone = FeedTransport(responses: [
      .json(
        pageJSON(
          items: ["{\"id\":\"internal:a\",\"kind\":\"removed\",\"revision\":1}"], hasMore: false,
          pageCursor: nil, syncCursor: "sync-1"), etag: nil)
    ])
    await #expect(throws: SightingFeedError.self) {
      _ = try await SightingFeedRepository(
        api: api(historyTombstone), cache: MemoryBrowseCacheStore()
      ).load()
    }

    let malformedSyncPages = [
      syncPageJSON(
        items: [internalJSON(id: "internal:a", revision: 2)], hasMore: false, syncCursor: "sync-1"),
      syncPageJSON(items: [], hasMore: true, syncCursor: "sync-2"),
      syncPageJSON(
        items: [
          internalJSON(id: "internal:a", revision: 3), internalJSON(id: "internal:b", revision: 2),
        ], hasMore: false, syncCursor: "sync-3"),
      syncPageJSON(
        items: [
          internalJSON(id: "internal:a", revision: 2), internalJSON(id: "internal:b", revision: 2),
        ], hasMore: false, syncCursor: "sync-3"),
    ]
    for malformed in malformedSyncPages {
      let transport = FeedTransport(responses: [
        .json(
          pageJSON(items: [], hasMore: false, pageCursor: nil, syncCursor: "sync-1"), etag: nil),
        .json(malformed, etag: nil),
      ])
      let repository = SightingFeedRepository(api: api(transport), cache: MemoryBrowseCacheStore())
      _ = try await repository.load()
      await #expect(throws: SightingFeedError.self) { _ = try await repository.refresh() }
    }

    let terminalCycle = FeedTransport(responses: [
      .json(pageJSON(items: [], hasMore: false, pageCursor: nil, syncCursor: "sync-a"), etag: nil),
      .json(
        syncPageJSON(
          items: [internalJSON(id: "internal:a", revision: 1)], hasMore: true,
          syncCursor: "sync-b"), etag: nil),
      .json(
        syncPageJSON(
          items: [internalJSON(id: "internal:a", revision: 2)], hasMore: false,
          syncCursor: "sync-a"), etag: nil),
    ])
    let cyclingRepository = SightingFeedRepository(
      api: api(terminalCycle), cache: MemoryBrowseCacheStore()
    )
    _ = try await cyclingRepository.load()
    await #expect(throws: SightingFeedError.cursorDidNotProgress) {
      _ = try await cyclingRepository.refresh()
    }
  }

  @Test("A retired flight cannot overwrite a replacement while persistence suspends")
  func retiredFlightCannotCommit() async throws {
    let cache = DelayedFirstWriteCache()
    let transport = FeedTransport(responses: [
      .json(
        pageJSON(
          items: [internalJSON(id: "internal:old", revision: 1)], hasMore: false,
          pageCursor: nil, syncCursor: "sync-old"), etag: "\"old\""),
      .json(
        pageJSON(
          items: [internalJSON(id: "internal:new", revision: 2)], hasMore: false,
          pageCursor: nil, syncCursor: "sync-new"), etag: "\"new\""),
    ])
    let repository = SightingFeedRepository(api: api(transport), cache: cache)
    let retired = Task { try await repository.load() }
    await eventually { await cache.firstWriteWaiting }

    retired.cancel()
    await #expect(throws: CancellationError.self) { _ = try await retired.value }
    let replacementTask = Task { try await repository.load() }
    await eventually { await transport.requests.count == 2 }
    await cache.releaseFirstWrite()
    let replacement = try await replacementTask.value
    #expect(replacement.items.map(\.id) == ["internal:new"])
    await eventually { await cache.firstWriteReturned }
    try await Task.sleep(for: .milliseconds(10))
    #expect(try await repository.load().items.map(\.id) == ["internal:new"])
    let key = BrowseCacheKey(resource: "sighting-feed", identity: "global")
    let stored = try await cache.load(SightingFeedState.self, for: key)
    guard case .value(let storedState) = stored?.payload else {
      Issue.record("Expected the replacement flight in the cache")
      return
    }
    #expect(storedState.items.map(\.id) == ["internal:new"])
  }

  @Test("Invalid cached provider and size state is never used as fallback")
  func rejectsInvalidCacheState() async throws {
    let cache = MemoryBrowseCacheStore()
    let key = BrowseCacheKey(resource: "sighting-feed", identity: "global")
    let invalid = SightingFeedState(items: [], tombstones: [:], syncCursor: "sync-1", providers: [])
    try await cache.replace(
      BrowseCacheDocument(resource: key.resource, fetchedAt: Date(), payload: .value(invalid)),
      for: key
    )
    let repository = SightingFeedRepository(
      api: api(FeedTransport(responses: [.failure])), cache: cache
    )

    await #expect(throws: Error.self) { _ = try await repository.load() }
  }

  @Test("A failed atomic cache write does not discard a complete response")
  func cacheWriteFailureRetainsSuccess() async throws {
    let cachedItem = try decodeItem(internalJSON(id: "internal:cached", revision: 1))
    let cached = SightingFeedState(
      items: [cachedItem], tombstones: [:], syncCursor: "sync-cached", providers: providers()
    )
    let cache = FailingWriteCache()
    try await cache.seed(cached)
    let transport = FeedTransport(responses: [
      .json(
        pageJSON(
          items: [internalJSON(id: "internal:a", revision: 2)], hasMore: false, pageCursor: nil,
          syncCursor: "sync-1"), etag: nil)
    ])
    let repository = SightingFeedRepository(api: api(transport), cache: cache)

    let state = try await repository.load()
    let key = BrowseCacheKey(resource: "sighting-feed", identity: "global")
    let stored = try await cache.load(SightingFeedState.self, for: key)

    #expect(state.items.map(\.id) == ["internal:a"])
    guard case .value(let storedState) = stored?.payload else {
      Issue.record("Expected the original cached state")
      return
    }
    #expect(storedState.items.map(\.id) == ["internal:cached"])
  }

  @Test("An older-page failure retains the complete visible first page")
  func olderPageFailureRetainsFirstPage() async throws {
    let cache = MemoryBrowseCacheStore()
    let cachedItem = try decodeItem(internalJSON(id: "internal:cached", revision: 7))
    let cached = SightingFeedState(
      items: [cachedItem], tombstones: [:], syncCursor: "sync-7", providers: providers()
    )
    let key = BrowseCacheKey(resource: "sighting-feed", identity: "global")
    try await cache.replace(
      BrowseCacheDocument(resource: key.resource, fetchedAt: Date(), payload: .value(cached)),
      for: key
    )
    let transport = FeedTransport(responses: [
      .json(
        pageJSON(
          items: [internalJSON(id: "internal:partial", revision: 8)], hasMore: true,
          pageCursor: "page-2", syncCursor: "sync-8"), etag: nil),
      .failure,
    ])
    let repository = SightingFeedRepository(api: api(transport), cache: cache)

    let result = try await repository.load()
    await #expect(throws: Error.self) { _ = try await repository.loadMore() }
    let stored = try await cache.load(SightingFeedState.self, for: key)

    #expect(result.items.map(\.id) == ["internal:partial"])
    #expect(try await repository.load().items.map(\.id) == ["internal:partial"])
    #expect(stored?.payload == .value(result))
  }

  @Test("Concurrent initial and manual refreshes coalesce into one request")
  func coalescesOverlappingRefreshes() async throws {
    let transport = FeedTransport(
      responses: [
        .json(pageJSON(items: [], hasMore: false, pageCursor: nil, syncCursor: "sync-1"), etag: nil)
      ],
      delay: .milliseconds(30)
    )
    let repository = SightingFeedRepository(api: api(transport), cache: MemoryBrowseCacheStore())

    async let initial = repository.load()
    async let manual = repository.refresh()
    _ = try await (initial, manual)

    #expect(await transport.requests.count == 1)
  }

  @Test("Cancelling one waiter preserves and commits shared success for a survivor")
  func cancellationPreservesSharedSuccess() async throws {
    let transport = CancellableFeedTransport()
    let cache = MemoryBrowseCacheStore()
    let repository = SightingFeedRepository(api: api(transport), cache: cache)
    let owner = Task { try await repository.load() }
    await eventually { await transport.isWaiting }
    let survivor = Task { try await repository.load() }
    try await Task.sleep(for: .milliseconds(10))

    owner.cancel()
    await transport.succeed(
      pageJSON(
        items: [internalJSON(id: "internal:shared", revision: 1)], hasMore: false, pageCursor: nil,
        syncCursor: "sync-1")
    )

    await #expect(throws: CancellationError.self) { _ = try await owner.value }
    #expect(try await survivor.value.items.map(\.id) == ["internal:shared"])
    let key = BrowseCacheKey(resource: "sighting-feed", identity: "global")
    #expect(try await cache.load(SightingFeedState.self, for: key) != nil)
    #expect(await transport.requestCount == 1)
  }

  @Test("Cancelling the last waiter cancels an in-flight transport")
  func lastCancellationCancelsTransport() async {
    let transport = CancellableFeedTransport()
    let repository = SightingFeedRepository(api: api(transport), cache: MemoryBrowseCacheStore())
    let load = Task { try await repository.load() }
    await eventually { await transport.isWaiting }

    load.cancel()

    await #expect(throws: CancellationError.self) { _ = try await load.value }
    await eventually { await transport.wasCancelled }
    #expect(await transport.wasCancelled)
  }

  private func decodeItem(_ json: String) throws -> SightingFeedItem {
    try JSONDecoder.fluke.decode(SightingFeedItem.self, from: Data(json.utf8))
  }

  private func internalJSON(
    id: String,
    revision: Int,
    observedAt: String = "2026-07-18T10:00:00Z"
  ) -> String {
    """
    {"behaviorNotes":null,"ecotypeGuess":"RESIDENT","groupSize":4,"id":"\(id)","identifiedWhales":[],"kind":"internal","latitude":48.5,"locationName":"Salish Sea","longitude":-123.2,"observedAt":"\(observedAt)","photos":[],"revision":\(revision)}
    """
  }

  private func externalJSON(id: String, revision: Int, observedAt: String) -> String {
    """
    {"attribution":"CWR","ecotypeGuess":null,"groupSize":3,"id":"\(id)","kind":"external","latitude":48.4,"longitude":-123.1,"notes":null,"observedAt":"\(observedAt)","revision":\(revision),"source":"CWR","sourceUrl":"https://example.test/record","species":"Orcinus orca","trusted":true}
    """
  }

  private func pageJSON(items: [String], hasMore: Bool, pageCursor: String?, syncCursor: String)
    -> String
  {
    let cursor = pageCursor.map { "\"\($0)\"" } ?? "null"
    return """
      {"hasMore":\(hasMore),"items":[\(items.joined(separator: ","))],"pageCursor":\(cursor),"providers":[{"expectedMaximumLag":25200,"lastAttemptAt":null,"lastSuccessAt":null,"provider":"acartia","status":"NEVER_RUN"},{"expectedMaximumLag":691200,"lastAttemptAt":null,"lastSuccessAt":null,"provider":"gbif","status":"NEVER_RUN"}],"syncCursor":"\(syncCursor)"}
      """
  }

  private func syncPageJSON(items: [String], hasMore: Bool, syncCursor: String) -> String {
    let providers =
      "{\"expectedMaximumLag\":25200,\"lastAttemptAt\":null,\"lastSuccessAt\":null,\"provider\":\"acartia\",\"status\":\"NEVER_RUN\"},{\"expectedMaximumLag\":691200,\"lastAttemptAt\":null,\"lastSuccessAt\":null,\"provider\":\"gbif\",\"status\":\"NEVER_RUN\"}"
    return
      "{\"hasMore\":\(hasMore),\"items\":[\(items.joined(separator: ","))],\"pageCursor\":null,\"providers\":[\(providers)],\"syncCursor\":\"\(syncCursor)\"}"
  }

  private func api(_ transport: any HTTPTransport) -> APIClient {
    APIClient(baseURL: URL(string: "https://api.fluke.app")!, transport: transport)
  }

  private func providers(at date: Date? = nil) -> [ProviderFreshness] {
    FeedProvider.allCases.map {
      ProviderFreshness(
        expectedMaximumLag: 300, lastAttemptAt: date, lastSuccessAt: date,
        provider: $0, status: .succeeded
      )
    }
  }

  private func eventually(_ condition: @escaping @Sendable () async -> Bool) async {
    for _ in 0..<1_000 {
      if await condition() { return }
      try? await Task.sleep(for: .milliseconds(1))
    }
  }
}

private actor FailingWriteCache: BrowseCacheStore {
  private let backing = MemoryBrowseCacheStore()

  func seed(_ state: SightingFeedState) async throws {
    let key = BrowseCacheKey(resource: "sighting-feed", identity: "global")
    try await backing.replace(
      BrowseCacheDocument(resource: key.resource, fetchedAt: Date(), payload: .value(state)),
      for: key
    )
  }

  func load<Value: Codable & Sendable>(
    _ type: Value.Type,
    for key: BrowseCacheKey
  ) async throws -> BrowseCacheDocument<Value>? {
    try await backing.load(type, for: key)
  }

  func replace<Value: Codable & Sendable>(
    _ document: BrowseCacheDocument<Value>,
    for key: BrowseCacheKey
  ) async throws { throw BrowseCacheError.corruptDocument }

  func remove(_ key: BrowseCacheKey) async throws {}
}

private actor DelayedFirstWriteCache: BrowseCacheStore {
  private var data: Data?
  private var writeCount = 0
  private var firstWriteContinuation: CheckedContinuation<Void, Never>?
  private(set) var firstWriteWaiting = false
  private(set) var firstWriteReturned = false

  func load<Value: Codable & Sendable>(
    _ type: Value.Type,
    for key: BrowseCacheKey
  ) async throws -> BrowseCacheDocument<Value>? {
    guard let data else { return nil }
    return try JSONDecoder.fluke.decode(BrowseCacheDocument<Value>.self, from: data)
  }

  func replace<Value: Codable & Sendable>(
    _ document: BrowseCacheDocument<Value>,
    for key: BrowseCacheKey
  ) async throws {
    writeCount += 1
    let encoded = try JSONEncoder.fluke.encode(document)
    if writeCount == 1 {
      firstWriteWaiting = true
      await withCheckedContinuation { firstWriteContinuation = $0 }
      firstWriteReturned = true
    }
    data = encoded
  }

  func remove(_ key: BrowseCacheKey) async throws {}

  func releaseFirstWrite() {
    let continuation = firstWriteContinuation
    firstWriteContinuation = nil
    continuation?.resume()
  }
}

private actor FeedTransport: HTTPTransport {
  enum Response: Sendable {
    case json(String, etag: String?)
    case notModified(etag: String?)
    case failure
  }

  private var responses: [Response]
  private let delay: Duration
  private(set) var requests: [URLRequest] = []

  init(responses: [Response], delay: Duration = .zero) {
    self.responses = responses
    self.delay = delay
  }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    requests.append(request)
    try await Task.sleep(for: delay)
    guard !responses.isEmpty, let url = request.url else { throw APIError.transport }
    let response = responses.removeFirst()
    let status: Int
    let body: Data
    let etag: String?
    switch response {
    case .json(let json, let value): (status, body, etag) = (200, Data(json.utf8), value)
    case .notModified(let value): (status, body, etag) = (304, Data(), value)
    case .failure: throw URLError(.networkConnectionLost)
    }
    let headers = etag.map { ["ETag": $0] }
    return (
      body, HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!
    )
  }
}

private actor CancellableFeedTransport: HTTPTransport {
  private var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?
  private var url: URL?
  private(set) var requestCount = 0
  private(set) var wasCancelled = false
  private(set) var isWaiting = false

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    requestCount += 1
    url = request.url
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        continuation = $0
        isWaiting = true
      }
    } onCancel: {
      Task { await self.cancel() }
    }
  }

  func succeed(_ json: String) {
    guard let continuation, let url else { return }
    self.continuation = nil
    isWaiting = false
    continuation.resume(
      returning: (
        Data(json.utf8),
        HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
      )
    )
  }

  private func cancel() {
    wasCancelled = true
    let continuation = self.continuation
    self.continuation = nil
    isWaiting = false
    continuation?.resume(throwing: CancellationError())
  }
}
