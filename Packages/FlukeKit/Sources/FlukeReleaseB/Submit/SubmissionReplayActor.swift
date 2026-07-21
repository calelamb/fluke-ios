import Foundation

public actor SubmissionReplayActor {
  private let queue: SubmissionQueue
  private let service: any SubmissionServiceProtocol
  private let invalidator: any SubmissionInvalidating
  private var isFlushing = false

  public init(
    queue: SubmissionQueue,
    service: any SubmissionServiceProtocol,
    invalidator: any SubmissionInvalidating = NoopSubmissionInvalidator()
  ) {
    self.queue = queue
    self.service = service
    self.invalidator = invalidator
  }

  public func flush() async {
    guard !isFlushing else { return }
    isFlushing = true
    defer { isFlushing = false }
    try? await queue.reconcileStorage()
    guard let entries = try? await queue.list() else { return }
    for entry in entries where entry.state == .queued {
      if Task.isCancelled { return }
      do {
        let photos = try await queue.photos(for: entry)
        _ = try await service.submit(payload: entry.payload, photos: photos)
        try await queue.discard(id: entry.id)
        await invalidator.ownerSightingsDidChange()
      } catch is CancellationError {
        return
      } catch SubmissionServiceError.partial(let receipt, let indices) {
        try? await queue.retainPartial(id: entry.id, receipt: receipt, indices: indices)
      } catch {
        try? await queue.recordFailure(id: entry.id)
      }
    }
  }
}
