import FlukeKit
import Foundation
import OSLog

public protocol SightingFeedRepositoryProtocol: Sendable {
  func updates() -> AsyncThrowingStream<SightingFeedState, Error>
  func hasMoreHistory() async -> Bool
  func load() async throws -> SightingFeedState
  func loadMore() async throws -> SightingFeedState
  func refresh() async throws -> SightingFeedState
}

extension SightingFeedRepositoryProtocol {
  public func updates() -> AsyncThrowingStream<SightingFeedState, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          continuation.yield(try await load())
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  public func hasMoreHistory() async -> Bool { false }

  public func loadMore() async throws -> SightingFeedState {
    try await load()
  }
}

public enum SightingFeedError: Error, Equatable, Sendable {
  case cursorDidNotProgress
  case invalidCursorMode
  case missingConditionalRepresentation
  case pageLimitExceeded
  case snapshotChanged
  case itemLimitExceeded
  case invalidRevisionOrder
  case tombstoneInHistory
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
  private var flight: Flight?
  private var history = HistoryPagination.none
  private var loadMoreFlight: LoadMoreFlight?
  private var persistenceTail: Task<Void, Never>?

  public init(api: APIClient, cache: any BrowseCacheStore) {
    self.api = api
    self.cache = cache
  }

  public func load() async throws -> SightingFeedState {
    try Task.checkCancellation()
    if let state { return state }
    return try await waitForFlight(initial: true)
  }

  public nonisolated func updates() -> AsyncThrowingStream<SightingFeedState, Error> {
    let cache = cache
    return AsyncThrowingStream { continuation in
      let task = Task {
        do {
          if let cached = try await Self.cachedState(from: cache) {
            continuation.yield(cached)
          }
          continuation.yield(try await self.load())
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  public func hasMoreHistory() async -> Bool {
    history.nextCursor != nil
  }

  public func loadMore() async throws -> SightingFeedState {
    try Task.checkCancellation()
    if let loadMoreFlight {
      return try await completeLoadMore(loadMoreFlight)
    }
    guard let base = state else { return try await load() }
    guard let cursor = history.nextCursor, let snapshot = history.snapshotCursor else { return base }
    let flight = makeLoadMoreFlight(base: base, cursor: cursor, snapshot: snapshot)
    loadMoreFlight = flight
    return try await completeLoadMore(flight)
  }

  public func refresh() async throws -> SightingFeedState {
    try Task.checkCancellation()
    return try await waitForFlight(initial: state == nil)
  }

  private func waitForFlight(initial: Bool) async throws -> SightingFeedState {
    let waiterID = UUID()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        register(waiterID, continuation: continuation, initial: initial)
      }
    } onCancel: {
      Task { await self.cancel(waiterID) }
    }
  }

  private func register(
    _ waiterID: UUID,
    continuation: CheckedContinuation<SightingFeedState, Error>,
    initial: Bool
  ) {
    if flight == nil { startFlight(initial: initial) }
    flight?.waiters[waiterID] = continuation
  }

  private func startFlight(initial: Bool) {
    let flightID = UUID()
    let worker =
      initial
      ? makeInitialTask(representations: representations)
      : makeTask(base: state, representations: representations)
    flight = Flight(id: flightID, worker: worker, waiters: [:])
    Task {
      let result = await worker.result
      await finish(flightID, result: result)
    }
  }

  private func cancel(_ waiterID: UUID) {
    guard var current = flight else { return }
    guard let continuation = current.waiters.removeValue(forKey: waiterID) else { return }
    continuation.resume(throwing: CancellationError())
    guard !current.waiters.isEmpty else {
      flight = nil
      current.worker.cancel()
      return
    }
    flight = current
  }

  private func finish(
    _ flightID: UUID,
    result: Result<FetchResult, Error>
  ) async {
    guard let current = flight, current.id == flightID else { return }
    switch result {
    case .success(let fetched):
      if fetched.shouldPersist { await persist(fetched.state) }
      guard let current = flight, current.id == flightID else { return }
      state = fetched.state
      representations = fetched.representations
      if let pagination = fetched.pagination { history = pagination }
      complete(flightID, with: .success(fetched.state))
    case .failure(let error):
      complete(flightID, with: .failure(error))
    }
  }

  private func complete(
    _ flightID: UUID,
    with result: Result<SightingFeedState, Error>
  ) {
    guard let current = flight, current.id == flightID else { return }
    flight = nil
    for continuation in current.waiters.values {
      continuation.resume(with: result)
    }
  }

  private func makeInitialTask(
    representations: [RequestIdentity: CachedRepresentation]
  ) -> Task<FetchResult, Error> {
    let api = api
    let cache = cache
    return Task.detached {
      let cached = try await Self.cachedState(from: cache)
      do {
        return try await Self.fetchFirstPage(api: api, representations: representations)
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        guard let cached else { throw error }
        return FetchResult(
          state: cached,
          representations: representations,
          pagination: nil,
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
    return Task.detached {
      if let base {
        return try await Self.fetchSync(api: api, base: base, representations: representations)
      }
      return try await Self.fetchFirstPage(api: api, representations: representations)
    }
  }

  private static func cachedState(from cache: any BrowseCacheStore) async throws
    -> SightingFeedState?
  {
    let document: BrowseCacheDocument<SightingFeedState>?
    do {
      document = try await cache.load(SightingFeedState.self, for: Self.cacheKey)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      logger.error(
        "Sighting feed cache read failed: \(String(describing: error), privacy: .private)")
      return nil
    }
    guard let document else { return nil }
    guard case .value(let value) = document.payload else { return nil }
    return value
  }

  private func persist(_ value: SightingFeedState) async {
    let predecessor = persistenceTail
    let cache = cache
    let task = Task.detached {
      await predecessor?.value
      do {
        try await cache.replace(
          BrowseCacheDocument(
            resource: Self.cacheKey.resource, fetchedAt: Date(), payload: .value(value)),
          for: Self.cacheKey
        )
      } catch {
        Self.logger.error(
          "Sighting feed cache write failed: \(String(describing: error), privacy: .private)")
      }
    }
    persistenceTail = task
    await task.value
  }

  private static func fetchFirstPage(
    api: APIClient,
    representations initialRepresentations: [RequestIdentity: CachedRepresentation]
  ) async throws -> FetchResult {
    var representations = initialRepresentations
    try Task.checkCancellation()
    let page = try await fetchPage(
      api: api, identity: .history(nil), representations: &representations)
    guard page.items.allSatisfy({ $0.observedAt != nil }) else {
      throw SightingFeedError.tombstoneInHistory
    }
    try checkItems(page.items.count)
    let next = try historyCursor(page)
    let state = SightingFeedState(
      items: [], tombstones: [:], syncCursor: page.syncCursor, providers: page.providers
    )
    .applying(items: page.items, syncCursor: page.syncCursor, providers: page.providers)
    return FetchResult(
      state: state,
      representations: [:],
      pagination: HistoryPagination(
        nextCursor: next, snapshotCursor: page.syncCursor, visitedCursors: [], pages: 1
      ),
      shouldPersist: true
    )
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
    var lastRevision = 0
    while true {
      try Task.checkCancellation()
      try checkBeforeFetch(pages: pages)
      guard visitedCursors.insert(cursor).inserted else {
        throw SightingFeedError.cursorDidNotProgress
      }
      let identity = RequestIdentity.sync(cursor)
      let page = try await fetchPage(
        api: api, identity: identity, representations: &representations)
      pages += 1
      itemCount += page.items.count
      try checkItems(itemCount)
      guard page.pageCursor == nil else { throw SightingFeedError.invalidCursorMode }
      guard !page.hasMore || !page.items.isEmpty else { throw SightingFeedError.invalidCursorMode }
      guard page.items.isEmpty || page.syncCursor != cursor else {
        throw SightingFeedError.cursorDidNotProgress
      }
      guard page.syncCursor == cursor || !visitedCursors.contains(page.syncCursor) else {
        throw SightingFeedError.cursorDidNotProgress
      }
      for item in page.items {
        guard item.revision > lastRevision else { throw SightingFeedError.invalidRevisionOrder }
        lastRevision = item.revision
      }
      state = state.applying(
        items: page.items, syncCursor: page.syncCursor, providers: page.providers)
      cursor = page.syncCursor
      if !page.hasMore { break }
    }
    let reusableIdentity = RequestIdentity.sync(state.syncCursor)
    let reusable = representations[reusableIdentity].map { [reusableIdentity: $0] } ?? [:]
    return FetchResult(
      state: state, representations: reusable, pagination: nil, shouldPersist: true
    )
  }

  private func makeLoadMoreFlight(
    base: SightingFeedState,
    cursor: String,
    snapshot: String
  ) -> LoadMoreFlight {
    let id = UUID()
    let api = api
    let representations = representations
    let pagination = history
    let task = Task.detached {
      try await Self.fetchHistoryPage(
        api: api, base: base, cursor: cursor, snapshot: snapshot,
        pagination: pagination, representations: representations
      )
    }
    return LoadMoreFlight(id: id, task: task)
  }

  private func completeLoadMore(_ flight: LoadMoreFlight) async throws -> SightingFeedState {
    let fetched = try await flight.task.value
    guard loadMoreFlight?.id == flight.id else { return state ?? fetched.state }
    loadMoreFlight = nil
    state = fetched.state
    representations = fetched.representations
    if let pagination = fetched.pagination { history = pagination }
    if fetched.shouldPersist { await persist(fetched.state) }
    return fetched.state
  }

  private static func fetchHistoryPage(
    api: APIClient,
    base: SightingFeedState,
    cursor: String,
    snapshot: String,
    pagination: HistoryPagination,
    representations initialRepresentations: [RequestIdentity: CachedRepresentation]
  ) async throws -> FetchResult {
    try checkBeforeFetch(pages: pagination.pages)
    guard !pagination.visitedCursors.contains(cursor) else {
      throw SightingFeedError.cursorDidNotProgress
    }
    var representations = initialRepresentations
    let page = try await fetchPage(
      api: api, identity: .history(cursor), representations: &representations)
    guard page.syncCursor == snapshot else { throw SightingFeedError.snapshotChanged }
    guard page.items.allSatisfy({ $0.observedAt != nil }) else {
      throw SightingFeedError.tombstoneInHistory
    }
    let merged = base.applying(
      items: page.items, syncCursor: base.syncCursor, providers: base.providers)
    try checkItems(merged.items.count)
    let next = try historyCursor(page)
    return FetchResult(
      state: merged,
      representations: representations,
      pagination: HistoryPagination(
        nextCursor: next,
        snapshotCursor: snapshot,
        visitedCursors: pagination.visitedCursors.union([cursor]),
        pages: pagination.pages + 1
      ),
      shouldPersist: true
    )
  }

  private static func historyCursor(_ page: SightingFeedPage) throws -> String? {
    if page.hasMore {
      guard let cursor = page.pageCursor else { throw SightingFeedError.invalidCursorMode }
      return cursor
    }
    guard page.pageCursor == nil else { throw SightingFeedError.invalidCursorMode }
    return nil
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
      representations[identity] = CachedRepresentation(
        entityTag: response.entityTag ?? existing.entityTag,
        page: existing.page
      )
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
  let pagination: HistoryPagination?
  let shouldPersist: Bool
}

private struct HistoryPagination: Sendable {
  let nextCursor: String?
  let snapshotCursor: String?
  let visitedCursors: Set<String>
  let pages: Int

  static let none = HistoryPagination(
    nextCursor: nil, snapshotCursor: nil, visitedCursors: [], pages: 0
  )
}

private struct LoadMoreFlight: Sendable {
  let id: UUID
  let task: Task<FetchResult, Error>
}

private struct Flight {
  let id: UUID
  let worker: Task<FetchResult, Error>
  var waiters: [UUID: CheckedContinuation<SightingFeedState, Error>]
}
