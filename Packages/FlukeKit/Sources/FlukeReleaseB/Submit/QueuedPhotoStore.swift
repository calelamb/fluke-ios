import CryptoKit
import Foundation

public enum QueuedPhotoStoreError: Error, Equatable, Sendable {
  case injectedFailure
  case invalidFileName
  case writeFailed
}

public actor QueuedPhotoStore {
  private let directory: URL
  private let failAfterWrites: Int?
  private let failAfterMoveAtIndex: Int?
  private let failRemoval: Bool
  private var completedWrites = 0

  public init(
    directory: URL,
    failAfterWrites: Int? = nil,
    failAfterMoveAtIndex: Int? = nil,
    failRemoval: Bool = false
  ) {
    self.directory = directory
    self.failAfterWrites = failAfterWrites
    self.failAfterMoveAtIndex = failAfterMoveAtIndex
    self.failRemoval = failRemoval
  }

  public func write(_ photos: [ProcessedPhoto], submissionID: UUID) throws -> [String] {
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
    )
    var written: [String] = []
    var temporaryURL: URL?
    do {
      for (index, photo) in photos.enumerated() {
        if let failAfterWrites, completedWrites >= failAfterWrites {
          throw QueuedPhotoStoreError.injectedFailure
        }
        let name = "\(submissionID.uuidString)_\(index)_\(photo.idempotencyID.uuidString).jpg"
        let finalURL = directory.appending(path: name)
        let currentTemporaryURL = directory.appending(path: ".\(name).\(UUID().uuidString).tmp")
        temporaryURL = currentTemporaryURL
        try photo.bytes.write(to: currentTemporaryURL, options: .atomic)
        try FileManager.default.moveItem(at: currentTemporaryURL, to: finalURL)
        temporaryURL = nil
        written.append(name)
        if failAfterMoveAtIndex == index { throw QueuedPhotoStoreError.injectedFailure }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = finalURL
        try mutableURL.setResourceValues(values)
        completedWrites += 1
      }
      return written
    } catch {
      if let temporaryURL { try? FileManager.default.removeItem(at: temporaryURL) }
      try? remove(written)
      throw error
    }
  }

  public func read(_ names: [String]) throws -> [ProcessedPhoto] {
    try names.map { name in
      let url = try validatedURL(for: name)
      let idempotencyID = Self.idempotencyID(for: name)
      return ProcessedPhoto(
        bytes: try Data(contentsOf: url),
        fileName: name,
        idempotencyID: idempotencyID
      )
    }
  }

  public func remove(_ names: [String]) throws {
    if failRemoval { throw QueuedPhotoStoreError.injectedFailure }
    for name in names {
      let url = try validatedURL(for: name)
      if FileManager.default.fileExists(atPath: url.path()) {
        try FileManager.default.removeItem(at: url)
      }
    }
  }

  private func validatedURL(for name: String) throws -> URL {
    guard !name.isEmpty, name == URL(filePath: name).lastPathComponent else {
      throw QueuedPhotoStoreError.invalidFileName
    }
    return directory.appending(path: name)
  }

  private static func idempotencyID(for name: String) -> UUID {
    if let rawID = name.split(separator: "_").last?.dropLast(4),
      let id = UUID(uuidString: String(rawID))
    {
      return id
    }
    let bytes = Array(SHA256.hash(data: Data(name.utf8)).prefix(16))
    return UUID(uuid: (
      bytes[0], bytes[1], bytes[2], bytes[3],
      bytes[4], bytes[5], bytes[6], bytes[7],
      bytes[8], bytes[9], bytes[10], bytes[11],
      bytes[12], bytes[13], bytes[14], bytes[15]
    ))
  }
}
