import Foundation

public actor SubmissionReplayActor {
  private let queue: SubmissionQueue
  private let service: any SubmissionServiceProtocol

  public init(queue: SubmissionQueue, service: any SubmissionServiceProtocol) {
    self.queue = queue
    self.service = service
  }

  public func flush() async {
    guard let entries = try? await queue.list() else { return }
    for entry in entries where entry.state == .queued {
      if Task.isCancelled { return }
      do {
        let photos = try await queue.photos(for: entry)
        _ = try await service.submit(payload: entry.payload, photos: photos)
        try await queue.discard(id: entry.id)
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
