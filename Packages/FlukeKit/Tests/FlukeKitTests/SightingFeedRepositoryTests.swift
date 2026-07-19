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

    let unknown = valid.replacingOccurrences(of: "\"revision\":1", with: "\"revision\":1,\"extra\":true")
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
      .replacingOccurrences(of: "\"photos\":[]", with: "\"photos\":[{\"id\":\"p1\",\"url\":\"file:///private\",\"thumbnailUrl\":\"https://example.test/t.jpg\",\"orderIndex\":0}]")
    #expect(throws: DecodingError.self) {
      try JSONDecoder.fluke.decode(SightingFeedItem.self, from: Data(badPhoto.utf8))
    }

    let badEcotype = internalJSON(id: "internal:one", revision: 1)
      .replacingOccurrences(of: "\"RESIDENT\"", with: "\"NEW_SERVER_VALUE\"")
    #expect(throws: DecodingError.self) {
      try JSONDecoder.fluke.decode(SightingFeedItem.self, from: Data(badEcotype.utf8))
    }
  }

  @Test("Only greater revisions apply and tombstone revisions remain")
  func immutableRevisionMerge() throws {
    let first = try decodeItem(internalJSON(id: "internal:one", revision: 4, observedAt: "2026-07-18T11:00:00Z"))
    let tie = try decodeItem(internalJSON(id: "internal:two", revision: 2, observedAt: "2026-07-18T11:00:00Z"))
    let initial = SightingFeedState(items: [tie, first], tombstones: [:], syncCursor: "r4", providers: [])
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

    let state = SightingFeedState(items: [old, new], tombstones: [:], syncCursor: "r2", providers: [])

    #expect(state.items.count == 1)
    #expect(state.items.first?.revision == 2)
  }

  @Test("Wire IDs remain unchanged and ordering is observedAt descending then ID")
  func stableOrderAndIdentity() throws {
    let laterB = try decodeItem(externalJSON(id: "external:CWR:b", revision: 2, observedAt: "2026-07-18T12:00:00Z"))
    let laterA = try decodeItem(internalJSON(id: "internal:a", revision: 1, observedAt: "2026-07-18T12:00:00Z"))
    let earlier = try decodeItem(internalJSON(id: "internal:z", revision: 3, observedAt: "2026-07-18T10:00:00Z"))
    let state = SightingFeedState(items: [earlier, laterB, laterA], tombstones: [:], syncCursor: "r3", providers: [])

    #expect(state.items.map(\.id) == ["external:CWR:b", "internal:a", "internal:z"])
  }

  @Test("Page decoder requires exact keys, two unique providers, and cursor semantics")
  func strictPage() throws {
    let page = pageJSON(items: [], hasMore: false, pageCursor: nil, syncCursor: "r1")
    _ = try JSONDecoder.fluke.decode(SightingFeedPage.self, from: Data(page.utf8))
    let extra = page.replacingOccurrences(of: "\"hasMore\":false", with: "\"hasMore\":false,\"extra\":0")
    #expect(throws: DecodingError.self) {
      try JSONDecoder.fluke.decode(SightingFeedPage.self, from: Data(extra.utf8))
    }
  }

  @Test("Freshness is live only when both providers are within their advertised lag")
  func providerFreshness() throws {
    let now = Date(timeIntervalSince1970: 1_721_303_200)
    let recent = now.addingTimeInterval(-60)
    let providers = [
      ProviderFreshness(expectedMaximumLag: 300, lastAttemptAt: recent, lastSuccessAt: recent, provider: .acartia, status: .succeeded),
      ProviderFreshness(expectedMaximumLag: 300, lastAttemptAt: recent, lastSuccessAt: recent, provider: .gbif, status: .failed),
    ]
    #expect(SightingFeedFreshness(providers: providers, now: now) == .live)
    #expect(SightingFeedFreshness(providers: Array(providers.dropLast()), now: now) == .recent(lastSuccessAge: 60))
  }

  @Test("History drains only page cursors and preserves one snapshot cursor")
  func drainsHistorySnapshot() async throws {
    let transport = FeedTransport(responses: [
      .json(pageJSON(items: [internalJSON(id: "internal:a", revision: 1)], hasMore: true, pageCursor: "page-2", syncCursor: "sync-1"), etag: "\"first\""),
      .json(pageJSON(items: [internalJSON(id: "internal:b", revision: 2)], hasMore: false, pageCursor: nil, syncCursor: "sync-1"), etag: "\"second\""),
    ])
    let repository = SightingFeedRepository(api: api(transport), cache: MemoryBrowseCacheStore())

    let state = try await repository.load()
    let requests = await transport.requests

    #expect(state.items.count == 2)
    #expect(requests.count == 2)
    #expect(requests[0].url?.query?.contains("pageCursor") == false)
    #expect(requests[0].url?.query?.contains("syncCursor") == false)
    #expect(requests[1].url?.query?.contains("pageCursor=page-2") == true)
    #expect(requests[1].url?.query?.contains("syncCursor") == false)
  }

  @Test("Sync drains returned sync cursors, never page cursors, and applies tombstones")
  func drainsSync() async throws {
    let transport = FeedTransport(responses: [
      .json(pageJSON(items: [internalJSON(id: "internal:a", revision: 1)], hasMore: false, pageCursor: nil, syncCursor: "sync-1"), etag: nil),
      .json(syncPageJSON(items: [internalJSON(id: "internal:a", revision: 2)], hasMore: true, syncCursor: "sync-2"), etag: nil),
      .json(syncPageJSON(items: ["{\"id\":\"internal:a\",\"kind\":\"removed\",\"revision\":3}"], hasMore: false, syncCursor: "sync-3"), etag: nil),
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
      .json(pageJSON(items: [], hasMore: false, pageCursor: nil, syncCursor: "sync-1"), etag: "\"history\""),
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

  @Test("A partial history failure returns and retains the complete last-known-good cache")
  func partialFailureRetainsCache() async throws {
    let cache = MemoryBrowseCacheStore()
    let cachedItem = try decodeItem(internalJSON(id: "internal:cached", revision: 7))
    let cached = SightingFeedState(items: [cachedItem], tombstones: [:], syncCursor: "sync-7", providers: [])
    let key = BrowseCacheKey(resource: "sighting-feed", identity: "global")
    try await cache.replace(
      BrowseCacheDocument(resource: key.resource, fetchedAt: Date(), payload: .value(cached)),
      for: key
    )
    let transport = FeedTransport(responses: [
      .json(pageJSON(items: [internalJSON(id: "internal:partial", revision: 8)], hasMore: true, pageCursor: "page-2", syncCursor: "sync-8"), etag: nil),
      .failure,
    ])
    let repository = SightingFeedRepository(api: api(transport), cache: cache)

    let result = try await repository.load()
    let stored = try await cache.load(SightingFeedState.self, for: key)

    #expect(result.items.map(\.id) == ["internal:cached"])
    #expect(stored?.payload == .value(cached))
  }

  @Test("Concurrent initial and manual refreshes coalesce into one request")
  func coalescesOverlappingRefreshes() async throws {
    let transport = FeedTransport(
      responses: [.json(pageJSON(items: [], hasMore: false, pageCursor: nil, syncCursor: "sync-1"), etag: nil)],
      delay: .milliseconds(30)
    )
    let repository = SightingFeedRepository(api: api(transport), cache: MemoryBrowseCacheStore())

    async let initial = repository.load()
    async let manual = repository.refresh()
    _ = try await (initial, manual)

    #expect(await transport.requests.count == 1)
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

  private func pageJSON(items: [String], hasMore: Bool, pageCursor: String?, syncCursor: String) -> String {
    let cursor = pageCursor.map { "\"\($0)\"" } ?? "null"
    return """
    {"hasMore":\(hasMore),"items":[\(items.joined(separator: ","))],"pageCursor":\(cursor),"providers":[{"expectedMaximumLag":25200,"lastAttemptAt":null,"lastSuccessAt":null,"provider":"acartia","status":"NEVER_RUN"},{"expectedMaximumLag":691200,"lastAttemptAt":null,"lastSuccessAt":null,"provider":"gbif","status":"NEVER_RUN"}],"syncCursor":"\(syncCursor)"}
    """
  }

  private func syncPageJSON(items: [String], hasMore: Bool, syncCursor: String) -> String {
    let providers = "{\"expectedMaximumLag\":25200,\"lastAttemptAt\":null,\"lastSuccessAt\":null,\"provider\":\"acartia\",\"status\":\"NEVER_RUN\"},{\"expectedMaximumLag\":691200,\"lastAttemptAt\":null,\"lastSuccessAt\":null,\"provider\":\"gbif\",\"status\":\"NEVER_RUN\"}"
    return "{\"hasMore\":\(hasMore),\"items\":[\(items.joined(separator: ","))],\"pageCursor\":null,\"providers\":[\(providers)],\"syncCursor\":\"\(syncCursor)\"}"
  }

  private func api(_ transport: FeedTransport) -> APIClient {
    APIClient(baseURL: URL(string: "https://api.fluke.app")!, transport: transport)
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
    return (body, HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!)
  }
}
