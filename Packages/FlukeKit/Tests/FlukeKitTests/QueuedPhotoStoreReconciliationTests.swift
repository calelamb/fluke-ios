import Foundation
import FlukeReleaseB
import Testing

@Suite("Queued photo staging reconciliation")
struct QueuedPhotoStoreReconciliationTests {
  @Test("A pending manifest cannot delete the SwiftData store or sidecars")
  func protectsDatabaseFiles() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let protectedNames = ["SubmissionQueue.store", "SubmissionQueue.store-shm", "SubmissionQueue.store-wal"]
    for name in protectedNames { try Data(name.utf8).write(to: directory.appending(path: name)) }
    try writeLegacyManifest(protectedNames, submissionID: UUID(), directory: directory)

    try await QueuedPhotoStore(directory: directory).reconcileStaging(liveFileNames: [])

    #expect(protectedNames.allSatisfy { FileManager.default.fileExists(atPath: directory.appending(path: $0).path()) })
    #expect(try quarantinedManifests(in: directory).count == 1)
  }

  @Test("Traversal and malformed names quarantine the whole manifest without deletion")
  func rejectsTraversalAndMalformedNames() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let directory = root.appending(path: "photos", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let outside = root.appending(path: "outside-\(UUID().uuidString).jpg")
    try Data([1]).write(to: outside)
    let malformed = "not-a-generated-photo.jpg"
    try Data([2]).write(to: directory.appending(path: malformed))
    try writeLegacyManifest(["../\(outside.lastPathComponent)", malformed], submissionID: UUID(), directory: directory)

    try await QueuedPhotoStore(directory: directory).reconcileStaging(liveFileNames: [])

    #expect(FileManager.default.fileExists(atPath: outside.path()))
    #expect(FileManager.default.fileExists(atPath: directory.appending(path: malformed).path()))
    #expect(try quarantinedManifests(in: directory).count == 1)
  }

  @Test("A manifest cannot claim a valid photo owned by another submission")
  func rejectsCrossSubmissionPhoto() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let ownerID = UUID()
    let manifestID = UUID()
    let name = generatedName(submissionID: ownerID, index: 0)
    try Data([3]).write(to: directory.appending(path: name))
    try writeLegacyManifest([name], submissionID: manifestID, directory: directory)

    try await QueuedPhotoStore(directory: directory).reconcileStaging(liveFileNames: [])

    #expect(FileManager.default.fileExists(atPath: directory.appending(path: name).path()))
    #expect(try quarantinedManifests(in: directory).count == 1)
  }

  @Test("Duplicate, noncontiguous, and oversized index sets are quarantined as a unit")
  func rejectsInvalidIndexSets() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let submissionID = UUID()
    let names = (0..<6).map { generatedName(submissionID: submissionID, index: $0) }
      + [generatedName(submissionID: submissionID, index: 0)]
    for name in Set(names) { try Data([4]).write(to: directory.appending(path: name)) }
    try writeLegacyManifest(names, submissionID: submissionID, directory: directory)

    try await QueuedPhotoStore(directory: directory).reconcileStaging(liveFileNames: [])

    #expect(Set(names).allSatisfy { FileManager.default.fileExists(atPath: directory.appending(path: $0).path()) })
    #expect(try quarantinedManifests(in: directory).count == 1)
  }

  @Test("Generated photo names require canonical UUIDs and decimal indices")
  func rejectsNoncanonicalGeneratedPattern() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let submissionID = UUID()
    let name = "\(submissionID.uuidString)_00_\(UUID().uuidString).jpg"
    try Data([6]).write(to: directory.appending(path: name))
    try writeBoundManifest([name], submissionID: submissionID, directory: directory)

    try await QueuedPhotoStore(directory: directory).reconcileStaging(liveFileNames: [])

    #expect(FileManager.default.fileExists(atPath: directory.appending(path: name).path()))
    #expect(try quarantinedManifests(in: directory).count == 1)
  }

  @Test("A legitimate manifest binds its schema to the submission and removes orphan photos")
  func legitimateOrphanRecovery() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let submissionID = UUID()
    let store = QueuedPhotoStore(directory: directory)
    let names = try await store.write(
      [ProcessedPhoto(bytes: Data([5]), fileName: "photo.jpg")],
      submissionID: submissionID
    )
    let pendingURL = directory.appending(path: ".pending-\(submissionID.uuidString).json")
    let json = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: pendingURL)) as? [String: Any]
    )
    #expect(json["submissionID"] as? String == submissionID.uuidString)

    try await store.reconcileStaging(liveFileNames: [])

    #expect(names.allSatisfy { !FileManager.default.fileExists(atPath: directory.appending(path: $0).path()) })
    #expect(!FileManager.default.fileExists(atPath: pendingURL.path()))
    #expect(try quarantinedManifests(in: directory).isEmpty)
  }
}

private func temporaryDirectory() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appending(path: UUID().uuidString, directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory
}

private func writeLegacyManifest(_ names: [String], submissionID: UUID, directory: URL) throws {
  try JSONEncoder().encode(names).write(
    to: directory.appending(path: ".pending-\(submissionID.uuidString).json")
  )
}

private func writeBoundManifest(_ names: [String], submissionID: UUID, directory: URL) throws {
  let value: [String: Any] = [
    "version": 1,
    "submissionID": submissionID.uuidString,
    "photoFileNames": names,
  ]
  try JSONSerialization.data(withJSONObject: value).write(
    to: directory.appending(path: ".pending-\(submissionID.uuidString).json")
  )
}

private func generatedName(submissionID: UUID, index: Int) -> String {
  "\(submissionID.uuidString)_\(index)_\(UUID().uuidString).jpg"
}

private func quarantinedManifests(in directory: URL) throws -> [String] {
  try FileManager.default.contentsOfDirectory(atPath: directory.path())
    .filter { $0.hasPrefix(".quarantine-") && $0.hasSuffix(".json") }
}
