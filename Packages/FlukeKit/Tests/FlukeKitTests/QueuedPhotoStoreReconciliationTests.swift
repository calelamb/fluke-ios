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
    try await assertBoundManifestIsQuarantined(
      names: protectedNames,
      submissionID: UUID(),
      directory: directory
    )
  }

  @Test("A bound manifest cannot traverse outside photo storage")
  func rejectsTraversal() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let directory = root.appending(path: "photos", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let outside = root.appending(path: "outside-\(UUID().uuidString).jpg")
    try Data([1]).write(to: outside)
    try writeBoundManifest(
      ["../\(outside.lastPathComponent)"],
      submissionID: UUID(),
      directory: directory
    )

    try await QueuedPhotoStore(directory: directory).reconcileStaging(liveFileNames: [])

    #expect(FileManager.default.fileExists(atPath: outside.path()))
    #expect(try quarantinedManifests(in: directory).count == 1)
  }

  @Test("Malformed generated filename patterns are quarantined")
  func rejectsMalformedNames() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let submissionID = UUID()
    let names = ["not-a-generated-photo.jpg"]
    for name in names { try Data([2]).write(to: directory.appending(path: name)) }

    try await assertBoundManifestIsQuarantined(
      names: names, submissionID: submissionID, directory: directory
    )
  }

  @Test("A generated filename with an invalid photo UUID is quarantined")
  func rejectsInvalidPhotoUUID() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let submissionID = UUID()
    let name = "\(submissionID.uuidString)_0_not-a-uuid.jpg"
    try Data([2]).write(to: directory.appending(path: name))
    try await assertBoundManifestIsQuarantined(
      names: [name], submissionID: submissionID, directory: directory
    )
  }

  @Test("A manifest cannot claim a valid photo owned by another submission")
  func rejectsCrossSubmissionPhoto() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let ownerID = UUID()
    let manifestID = UUID()
    let name = generatedName(submissionID: ownerID, index: 0)
    try Data([3]).write(to: directory.appending(path: name))
    try await assertBoundManifestIsQuarantined(
      names: [name], submissionID: manifestID, directory: directory
    )
  }

  @Test("Duplicate photo indices quarantine the complete bound manifest")
  func rejectsDuplicateIndices() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let submissionID = UUID()
    let names = [0, 0].map { generatedName(submissionID: submissionID, index: $0) }
    for name in names { try Data([4]).write(to: directory.appending(path: name)) }
    try await assertBoundManifestIsQuarantined(
      names: names, submissionID: submissionID, directory: directory
    )
  }

  @Test("Noncontiguous photo indices quarantine the complete bound manifest")
  func rejectsNoncontiguousIndices() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let submissionID = UUID()
    let names = [0, 2].map { generatedName(submissionID: submissionID, index: $0) }
    for name in names { try Data([4]).write(to: directory.appending(path: name)) }
    try await assertBoundManifestIsQuarantined(
      names: names, submissionID: submissionID, directory: directory
    )
  }

  @Test("More than five manifest photos are quarantined before index inspection")
  func rejectsOversizedManifest() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let submissionID = UUID()
    let names = (0..<6).map { generatedName(submissionID: submissionID, index: $0) }
    for name in names { try Data([4]).write(to: directory.appending(path: name)) }
    try await assertBoundManifestIsQuarantined(
      names: names, submissionID: submissionID, directory: directory
    )
  }

  @Test("An unsupported bound manifest schema version is quarantined")
  func rejectsWrongVersion() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let submissionID = UUID()
    let name = generatedName(submissionID: submissionID, index: 0)
    try Data([4]).write(to: directory.appending(path: name))
    try await assertBoundManifestIsQuarantined(
      names: [name], submissionID: submissionID, version: 2, directory: directory
    )
  }

  @Test("A payload submission ID that differs from the manifest filename is quarantined")
  func rejectsMismatchedPayloadSubmissionID() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileID = UUID()
    let payloadID = UUID()
    let name = generatedName(submissionID: payloadID, index: 0)
    try Data([4]).write(to: directory.appending(path: name))
    try await assertBoundManifestIsQuarantined(
      names: [name], submissionID: payloadID, fileSubmissionID: fileID,
      directory: directory
    )
  }

  @Test("Generated photo names require canonical UUIDs and decimal indices")
  func rejectsNoncanonicalGeneratedPattern() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let submissionID = UUID()
    let name = "\(submissionID.uuidString)_00_\(UUID().uuidString).jpg"
    try Data([6]).write(to: directory.appending(path: name))
    try await assertBoundManifestIsQuarantined(
      names: [name], submissionID: submissionID, directory: directory
    )
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

private func writeBoundManifest(
  _ names: [String],
  submissionID: UUID,
  fileSubmissionID: UUID? = nil,
  version: Int = 1,
  directory: URL
) throws {
  let value: [String: Any] = [
    "version": version,
    "submissionID": submissionID.uuidString,
    "photoFileNames": names,
  ]
  try JSONSerialization.data(withJSONObject: value).write(
    to: directory.appending(path: ".pending-\((fileSubmissionID ?? submissionID).uuidString).json")
  )
}

private func assertBoundManifestIsQuarantined(
  names: [String],
  submissionID: UUID,
  fileSubmissionID: UUID? = nil,
  version: Int = 1,
  directory: URL
) async throws {
  try writeBoundManifest(
    names,
    submissionID: submissionID,
    fileSubmissionID: fileSubmissionID,
    version: version,
    directory: directory
  )
  try await QueuedPhotoStore(directory: directory).reconcileStaging(liveFileNames: [])
  let siblingNames = names.filter { $0 == URL(filePath: $0).lastPathComponent }
  #expect(siblingNames.allSatisfy {
    FileManager.default.fileExists(atPath: directory.appending(path: $0).path())
  })
  #expect(try quarantinedManifests(in: directory).count == 1)
}

private func generatedName(submissionID: UUID, index: Int) -> String {
  "\(submissionID.uuidString)_\(index)_\(UUID().uuidString).jpg"
}

private func quarantinedManifests(in directory: URL) throws -> [String] {
  try FileManager.default.contentsOfDirectory(atPath: directory.path())
    .filter { $0.hasPrefix(".quarantine-") && $0.hasSuffix(".json") }
}
