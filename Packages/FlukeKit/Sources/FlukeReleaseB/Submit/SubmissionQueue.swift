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
  var cleanupFileNames: [String] = []
  var stateRawValue: String
  var attempts: Int
  var createdAt: Date

  init(value: QueuedSubmissionValue) throws {
    id = value.id
    payloadData = try JSONEncoder().encode(value.payload)
    photoFileNames = value.photoFileNames
    cleanupFileNames = []
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

public actor SubmissionQueue: SubmissionQueueProtocol, ModelActor {
  public nonisolated let modelContainer: ModelContainer
  public nonisolated let modelExecutor: any ModelExecutor
  private let photoStore: QueuedPhotoStore
  private let saveContext: (ModelContext) throws -> Void
  private var rowIdentifiers: [UUID: PersistentIdentifier]?

  private var context: ModelContext { modelContext }

  public init(
    directory: URL = SubmissionQueue.applicationSupportDirectory(),
    inMemory: Bool = false,
    photoStore: QueuedPhotoStore? = nil
  ) throws {
    try self.init(
      directory: directory,
      inMemory: inMemory,
      photoStore: photoStore,
      saveContext: { try $0.save() }
    )
  }

  init(
    directory: URL,
    inMemory: Bool = false,
    photoStore: QueuedPhotoStore? = nil,
    saveContext: @escaping (ModelContext) throws -> Void
  ) throws {
    let schema = Schema([QueuedSubmissionRow.self])
    let configuration: ModelConfiguration
    if inMemory {
      configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    } else {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      configuration = ModelConfiguration(
        "SubmissionQueue",
        schema: schema,
        url: directory.appending(path: "SubmissionQueue.store")
      )
    }
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let context = ModelContext(container)
    modelContainer = container
    modelExecutor = DefaultSerialModelExecutor(modelContext: context)
    self.photoStore = photoStore ?? QueuedPhotoStore(directory: directory)
    self.saveContext = saveContext
  }

  public func list() throws -> [QueuedSubmissionValue] {
    let rows = try context.fetch(FetchDescriptor<QueuedSubmissionRow>())
    return try rows
      .filter { $0.stateRawValue != QueuedSubmissionState.discarding.rawValue }
      .map { try $0.value() }
      .sorted { $0.createdAt < $1.createdAt }
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
      let row = try QueuedSubmissionRow(value: value)
      context.insert(row)
      try saveContext(context)
      register(row)
    } catch {
      context.rollback()
      do {
        try await photoStore.remove(names)
        try await photoStore.completeStaging(submissionID: id)
      } catch {
        // The staging manifest remains durable so reconcileStorage can retry cleanup.
      }
      throw error
    }
    do {
      try await photoStore.completeStaging(submissionID: id)
    } catch {
      // The saved row owns the bytes; reconciliation can safely remove the stale manifest.
    }
    return value
  }

  public func reconcileStorage() async throws {
    let rows = try context.fetch(FetchDescriptor<QueuedSubmissionRow>())
    for row in rows where row.stateRawValue == QueuedSubmissionState.discarding.rawValue {
      try await photoStore.remove(row.photoFileNames + row.cleanupFileNames)
      context.delete(row)
      try saveContext(context)
      unregister(id: row.id)
    }
    let retainedRows = try context.fetch(FetchDescriptor<QueuedSubmissionRow>())
    for row in retainedRows where !row.cleanupFileNames.isEmpty {
      try await photoStore.remove(row.cleanupFileNames)
      row.cleanupFileNames = []
      try saveContext(context)
    }
    let liveNames = Set(retainedRows.flatMap(\.photoFileNames))
    try await photoStore.reconcileStaging(liveFileNames: liveNames)
  }

  public func retry(id: UUID) throws {
    let row = try requiredRow(id: id)
    row.stateRawValue = QueuedSubmissionState.queued.rawValue
    row.attempts = 0
    try saveContext(context)
  }

  public func discard(id: UUID) async throws {
    let row = try requiredRow(id: id)
    let names = row.photoFileNames + row.cleanupFileNames
    row.stateRawValue = QueuedSubmissionState.discarding.rawValue
    try saveContext(context)
    try await photoStore.remove(names)
    context.delete(row)
    try saveContext(context)
    unregister(id: id)
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
    try saveContext(context)
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
    row.cleanupFileNames = removedNames
    row.attempts = 0
    row.stateRawValue = QueuedSubmissionState.queued.rawValue
    try saveContext(context)
    try await photoStore.remove(removedNames)
    row.cleanupFileNames = []
    try saveContext(context)
  }

  public func clearAccountAssociation() throws {
    let rows = try context.fetch(FetchDescriptor<QueuedSubmissionRow>())
    for row in rows {
      let value = try row.value()
      row.payloadData = try JSONEncoder().encode(value.payload.removingObserverEmail())
    }
    try saveContext(context)
  }

  public static func applicationSupportDirectory() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return base.appending(path: "app.fluke.Fluke/submissions", directoryHint: .isDirectory)
  }

  private func requiredRow(id: UUID) throws -> QueuedSubmissionRow {
    try loadRowIdentifiersIfNeeded()
    guard
      let persistentIdentifier = rowIdentifiers?[id],
      let row = context.model(for: persistentIdentifier) as? QueuedSubmissionRow
    else {
      throw SubmissionQueueError.missingEntry
    }
    return row
  }

  private func loadRowIdentifiersIfNeeded() throws {
    guard rowIdentifiers == nil else { return }
    let rows = try context.fetch(FetchDescriptor<QueuedSubmissionRow>())
    rowIdentifiers = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.persistentModelID) })
  }

  private func register(_ row: QueuedSubmissionRow) {
    guard let rowIdentifiers else { return }
    self.rowIdentifiers = rowIdentifiers.merging([row.id: row.persistentModelID]) { _, new in new }
  }

  private func unregister(id: UUID) {
    guard let rowIdentifiers else { return }
    self.rowIdentifiers = rowIdentifiers.filter { $0.key != id }
  }
}
