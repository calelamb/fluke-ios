import Foundation

public enum QueuedSubmissionState: String, Codable, Hashable, Sendable {
  case queued
  case failed
}

public struct QueuedSubmissionValue: Codable, Hashable, Identifiable, Sendable {
  public let id: UUID
  public let payload: SubmissionPayload
  public let photoFileNames: [String]
  public let state: QueuedSubmissionState
  public let attempts: Int
  public let createdAt: Date

  public init(
    id: UUID,
    payload: SubmissionPayload,
    photoFileNames: [String],
    state: QueuedSubmissionState,
    attempts: Int,
    createdAt: Date
  ) {
    self.id = id
    self.payload = payload
    self.photoFileNames = photoFileNames
    self.state = state
    self.attempts = attempts
    self.createdAt = createdAt
  }
}
