import Foundation
import SwiftData

public protocol SubmissionQueueProtocol: Sendable {
  func list() async throws -> [QueuedSubmissionValue]
  func enqueue(payload: SubmissionPayload, photos: [ProcessedPhoto]) async throws -> QueuedSubmissionValue
  func retry(id: UUID) async throws
  func discard(id: UUID) async throws
}

@Model
private final class QueuedSubmissionRow {
  @Attribute(.unique) var id: UUID
  var payloadData: Data
  var photoFileNames: [String]
  var stateRawValue: String
  var attempts: Int
  var createdAt: Date

  init(value: QueuedSubmissionValue) throws {
    id = value.id
    payloadData = try JSONEncoder().encode(value.payload)
    photoFileNames = value.photoFileNames
    stateRawValue = value.state.rawValue
    attempts = value.attempts
    createdAt = value.createdAt
  }

  func value() throws -> QueuedSubmissionValue {
    guard let state = QueuedSubmissionState(rawValue: stateRawValue) else {
      throw SubmissionQueueError.corruptRow
    }
    return QueuedSubmissionValue(
      id: id,
      payload: try JSONDecoder().decode(SubmissionPayload.self, from: payloadData),
      photoFileNames: photoFileNames,
      state: state,
      attempts: attempts,
      createdAt: createdAt
    )
  }
}

public enum SubmissionQueueError: Error, Equatable, Sendable {
  case missingEntry
  case corruptRow
  case invalidPartialFailure
}

public actor SubmissionQueue: SubmissionQueueProtocol {
  private let context: ModelContext
  private let photoStore: QueuedPhotoStore

  public init(
    directory: URL = SubmissionQueue.applicationSupportDirectory(),
    inMemory: Bool = false,
    photoStore: QueuedPhotoStore? = nil
  ) throws {
    let schema = Schema([QueuedSubmissionRow.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    context = ModelContext(container)
    self.photoStore = photoStore ?? QueuedPhotoStore(directory: directory)
  }

  public func list() throws -> [QueuedSubmissionValue] {
    let rows = try context.fetch(FetchDescriptor<QueuedSubmissionRow>())
    return try rows.map { try $0.value() }.sorted { $0.createdAt < $1.createdAt }
  }

  public func enqueue(
    payload: SubmissionPayload,
    photos: [ProcessedPhoto]
  ) async throws -> QueuedSubmissionValue {
    let id = UUID()
    let names = try await photoStore.write(photos, submissionID: id)
    let value = QueuedSubmissionValue(
      id: id, payload: payload, photoFileNames: names,
      state: .queued, attempts: 0, createdAt: Date()
    )
    do {
      context.insert(try QueuedSubmissionRow(value: value))
      try context.save()
      return value
    } catch {
      try? await photoStore.remove(names)
      throw error
    }
  }

  public func retry(id: UUID) throws {
    let row = try requiredRow(id: id)
    row.stateRawValue = QueuedSubmissionState.queued.rawValue
    row.attempts = 0
    try context.save()
  }

  public func discard(id: UUID) async throws {
    let row = try requiredRow(id: id)
    let names = row.photoFileNames
    context.delete(row)
    try context.save()
    try await photoStore.remove(names)
  }

  public func photoBytes(for value: QueuedSubmissionValue) async throws -> [Data] {
    try await photoStore.read(value.photoFileNames).map(\.bytes)
  }

  func photos(for value: QueuedSubmissionValue) async throws -> [ProcessedPhoto] {
    try await photoStore.read(value.photoFileNames)
  }

  func recordFailure(id: UUID) throws {
    let row = try requiredRow(id: id)
    row.attempts += 1
    if row.attempts >= 3 { row.stateRawValue = QueuedSubmissionState.failed.rawValue }
    try context.save()
  }

  func retainPartial(id: UUID, receipt: SubmissionReceipt, indices: [Int]) async throws {
    let row = try requiredRow(id: id)
    let old = try row.value()
    guard !indices.isEmpty, indices.allSatisfy(old.photoFileNames.indices.contains) else {
      throw SubmissionQueueError.invalidPartialFailure
    }
    let retainedNames = indices.map { old.photoFileNames[$0] }
    let removedNames = old.photoFileNames.filter { !retainedNames.contains($0) }
    row.payloadData = try JSONEncoder().encode(old.payload.resuming(receipt: receipt))
    row.photoFileNames = retainedNames
    row.attempts = 0
    row.stateRawValue = QueuedSubmissionState.queued.rawValue
    try context.save()
    try await photoStore.remove(removedNames)
  }

  public func clearAccountAssociation() throws {
    let rows = try context.fetch(FetchDescriptor<QueuedSubmissionRow>())
    for row in rows {
      let value = try row.value()
      row.payloadData = try JSONEncoder().encode(value.payload.removingObserverEmail())
    }
    try context.save()
  }

  public static func applicationSupportDirectory() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return base.appending(path: "app.fluke.Fluke/submissions", directoryHint: .isDirectory)
  }

  private func requiredRow(id: UUID) throws -> QueuedSubmissionRow {
    let descriptor = FetchDescriptor<QueuedSubmissionRow>(predicate: #Predicate { $0.id == id })
    guard let row = try context.fetch(descriptor).first else { throw SubmissionQueueError.missingEntry }
    return row
  }
}
