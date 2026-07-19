import FlukeKit
import Foundation
import OSLog

public protocol SightingFeedRepositoryProtocol: Sendable {
  func load() async throws -> SightingFeedState
  func refresh() async throws -> SightingFeedState
}

public enum SightingFeedError: Error, Equatable, Sendable {
  case cursorDidNotProgress
  case invalidCursorMode
  case missingConditionalRepresentation
  case pageLimitExceeded
  case snapshotChanged
  case itemLimitExceeded
}

public actor SightingFeedRepository: SightingFeedRepositoryProtocol {
  private static let logger = Logger(subsystem: "app.fluke", category: "sighting-feed")
  private static let cacheKey = BrowseCacheKey(resource: "sighting-feed", identity: "global")
  private static let maximumPages = 100
  private static let maximumItems = 10_000
  private static let pageLimit = 100

  private let api: APIClient
  private let cache: any BrowseCacheStore
  private var state: SightingFeedState?
  private var representations: [RequestIdentity: CachedRepresentation] = [:]
  private var inFlight: Task<FetchResult, Error>?

  public init(api: APIClient, cache: any BrowseCacheStore) {
    self.api = api
    self.cache = cache
  }

  public func load() async throws -> SightingFeedState {
    if let state { return state }
    if let inFlight { return try await inFlight.value.state }
    let task = makeInitialTask(representations: representations)
    inFlight = task
    do {
      let result = try await task.value
      if result.shouldPersist { try await persist(result.state) }
      state = result.state
      representations = result.representations
      inFlight = nil
      return result.state
    } catch {
      inFlight = nil
      throw error
    }
  }

  public func refresh() async throws -> SightingFeedState {
    if let inFlight { return try await inFlight.value.state }
    guard let baseState = state else { return try await load() }
    let task = makeTask(base: baseState, representations: representations)
    inFlight = task
    do {
      let result = try await task.value
      try await persist(result.state)
      state = result.state
      representations = result.representations
      inFlight = nil
      return result.state
    } catch {
      inFlight = nil
      throw error
    }
  }

  private func makeInitialTask(
    representations: [RequestIdentity: CachedRepresentation]
  ) -> Task<FetchResult, Error> {
    let api = api
    let cache = cache
    return Task {
      let cached = try await Self.cachedState(from: cache)
      do {
        return try await Self.fetchHistory(api: api, representations: representations)
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        guard let cached else { throw error }
        return FetchResult(
          state: cached,
          representations: representations,
          shouldPersist: false
        )
      }
    }
  }

  private func makeTask(
    base: SightingFeedState?,
    representations: [RequestIdentity: CachedRepresentation]
  ) -> Task<FetchResult, Error> {
    let api = api
    return Task {
      if let base {
        return try await Self.fetchSync(api: api, base: base, representations: representations)
      }
      return try await Self.fetchHistory(api: api, representations: representations)
    }
  }

  private static func cachedState(from cache: any BrowseCacheStore) async throws -> SightingFeedState? {
    let document: BrowseCacheDocument<SightingFeedState>?
    do {
      document = try await cache.load(SightingFeedState.self, for: Self.cacheKey)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      logger.error("Sighting feed cache read failed: \(String(describing: error), privacy: .private)")
      return nil
    }
    guard let document else { return nil }
    guard case .value(let value) = document.payload else { return nil }
    return value
  }

  private func persist(_ value: SightingFeedState) async throws {
    try Task.checkCancellation()
    do {
      try await cache.replace(
        BrowseCacheDocument(resource: Self.cacheKey.resource, fetchedAt: Date(), payload: .value(value)),
        for: Self.cacheKey
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      Self.logger.error("Sighting feed cache write failed: \(String(describing: error), privacy: .private)")
    }
  }

  private static func fetchHistory(
    api: APIClient,
    representations initialRepresentations: [RequestIdentity: CachedRepresentation]
  ) async throws -> FetchResult {
    var representations = initialRepresentations
    var pageCursor: String?
    var visitedCursors = Set<String>()
    var snapshotCursor: String?
    var allItems: [SightingFeedItem] = []
    var providers: [ProviderFreshness] = []
    var pages = 0
    repeat {
      try Task.checkCancellation()
      try checkBeforeFetch(pages: pages)
      let identity = RequestIdentity.history(pageCursor)
      let page = try await fetchPage(api: api, identity: identity, representations: &representations)
      pages += 1
      allItems += page.items
      try checkItems(allItems.count)
      if let snapshotCursor, snapshotCursor != page.syncCursor { throw SightingFeedError.snapshotChanged }
      snapshotCursor = page.syncCursor
      providers = page.providers
      guard page.hasMore else {
        pageCursor = nil
        break
      }
      guard let next = page.pageCursor else { throw SightingFeedError.invalidCursorMode }
      guard visitedCursors.insert(next).inserted else { throw SightingFeedError.cursorDidNotProgress }
      pageCursor = next
    } while pageCursor != nil
    guard let snapshotCursor else { throw APIError.malformedResponse }
    let state = SightingFeedState(items: [], tombstones: [:], syncCursor: snapshotCursor, providers: providers)
      .applying(items: allItems, syncCursor: snapshotCursor, providers: providers)
    return FetchResult(state: state, representations: representations, shouldPersist: true)
  }

  private static func fetchSync(
    api: APIClient,
    base: SightingFeedState,
    representations initialRepresentations: [RequestIdentity: CachedRepresentation]
  ) async throws -> FetchResult {
    var representations = initialRepresentations
    var cursor = base.syncCursor
    var visitedCursors = Set<String>()
    var state = base
    var pages = 0
    var itemCount = 0
    while true {
      try Task.checkCancellation()
      try checkBeforeFetch(pages: pages)
      guard visitedCursors.insert(cursor).inserted else {
        throw SightingFeedError.cursorDidNotProgress
      }
      let identity = RequestIdentity.sync(cursor)
      let page = try await fetchPage(api: api, identity: identity, representations: &representations)
      pages += 1
      itemCount += page.items.count
      try checkItems(itemCount)
      guard page.pageCursor == nil else { throw SightingFeedError.invalidCursorMode }
      if page.hasMore && page.syncCursor == cursor { throw SightingFeedError.cursorDidNotProgress }
      state = state.applying(items: page.items, syncCursor: page.syncCursor, providers: page.providers)
      cursor = page.syncCursor
      if !page.hasMore { break }
    }
    return FetchResult(state: state, representations: representations, shouldPersist: true)
  }

  private static func fetchPage(
    api: APIClient,
    identity: RequestIdentity,
    representations: inout [RequestIdentity: CachedRepresentation]
  ) async throws -> SightingFeedPage {
    let existing = representations[identity]
    let response: ConditionalGETResponse<SightingFeedPage> = try await api.conditionalGet(
      identity.request(limit: pageLimit),
      entityTag: existing?.entityTag
    )
    if response.isNotModified {
      guard let existing else { throw SightingFeedError.missingConditionalRepresentation }
      return existing.page
    }
    guard let page = response.value else { throw APIError.malformedResponse }
    representations[identity] = CachedRepresentation(entityTag: response.entityTag, page: page)
    return page
  }

  private static func checkBeforeFetch(pages: Int) throws {
    if pages >= maximumPages { throw SightingFeedError.pageLimitExceeded }
  }

  private static func checkItems(_ items: Int) throws {
    if items > maximumItems { throw SightingFeedError.itemLimitExceeded }
  }
}

private enum RequestIdentity: Hashable, Sendable {
  case history(String?)
  case sync(String)

  func request(limit: Int) -> APIRequest {
    var query = [URLQueryItem(name: "limit", value: String(limit))]
    switch self {
    case .history(let cursor):
      if let cursor { query.append(URLQueryItem(name: "pageCursor", value: cursor)) }
    case .sync(let cursor):
      query.append(URLQueryItem(name: "syncCursor", value: cursor))
    }
    return APIRequest(path: ReleaseBEndpoint.sightingFeed, queryItems: query)
  }
}

private struct CachedRepresentation: Sendable {
  let entityTag: String?
  let page: SightingFeedPage
}

private struct FetchResult: Sendable {
  let state: SightingFeedState
  let representations: [RequestIdentity: CachedRepresentation]
  let shouldPersist: Bool
}
