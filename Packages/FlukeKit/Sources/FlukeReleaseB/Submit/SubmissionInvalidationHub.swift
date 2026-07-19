import Foundation

public struct SubmissionInvalidation: Equatable, Sendable {
  public let revision: UInt64

  public init(revision: UInt64) {
    self.revision = revision
  }
}

public protocol SubmissionInvalidating: Sendable {
  func ownerSightingsDidChange() async
}

public protocol SubmissionInvalidationObserving: Sendable {
  func updates() async -> AsyncStream<SubmissionInvalidation>
}

public struct NoopSubmissionInvalidator: SubmissionInvalidating, Sendable {
  public init() {}
  public func ownerSightingsDidChange() async {}
}

public struct NoopSubmissionInvalidationObserver: SubmissionInvalidationObserving, Sendable {
  public init() {}
  public func updates() async -> AsyncStream<SubmissionInvalidation> {
    AsyncStream { $0.finish() }
  }
}

public actor SubmissionInvalidationHub: SubmissionInvalidating, SubmissionInvalidationObserving {
  private var revision: UInt64 = 0
  private var continuations: [UUID: AsyncStream<SubmissionInvalidation>.Continuation] = [:]

  public init() {}

  public func updates() -> AsyncStream<SubmissionInvalidation> {
    let subscriberID = UUID()
    let pair = AsyncStream.makeStream(
      of: SubmissionInvalidation.self,
      bufferingPolicy: .bufferingNewest(1)
    )
    continuations = continuations.merging([subscriberID: pair.continuation]) { _, new in new }
    pair.continuation.onTermination = { [weak self] _ in
      Task { await self?.removeSubscriber(subscriberID) }
    }
    return pair.stream
  }

  public func ownerSightingsDidChange() {
    revision &+= 1
    let event = SubmissionInvalidation(revision: revision)
    continuations.values.forEach { $0.yield(event) }
  }

  private func removeSubscriber(_ id: UUID) {
    continuations[id] = nil
  }
}
