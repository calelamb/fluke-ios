import Foundation

public enum QueuedPhotoStoreError: Error, Equatable, Sendable {
  case injectedFailure
  case invalidFileName
  case writeFailed
}

public actor QueuedPhotoStore {
  private let directory: URL
  private let failAfterWrites: Int?
  private var completedWrites = 0

  public init(directory: URL, failAfterWrites: Int? = nil) {
    self.directory = directory
    self.failAfterWrites = failAfterWrites
  }

  public func write(_ photos: [ProcessedPhoto], submissionID: UUID) throws -> [String] {
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
    )
    var written: [String] = []
    do {
      for (index, photo) in photos.enumerated() {
        if let failAfterWrites, completedWrites >= failAfterWrites {
          throw QueuedPhotoStoreError.injectedFailure
        }
        let name = "\(submissionID.uuidString)-\(index).jpg"
        let finalURL = directory.appending(path: name)
        let temporaryURL = directory.appending(path: ".\(name).\(UUID().uuidString).tmp")
        try photo.bytes.write(to: temporaryURL, options: .atomic)
        try FileManager.default.moveItem(at: temporaryURL, to: finalURL)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = finalURL
        try mutableURL.setResourceValues(values)
        written.append(name)
        completedWrites += 1
      }
      return written
    } catch {
      try? remove(written)
      throw error
    }
  }

  public func read(_ names: [String]) throws -> [ProcessedPhoto] {
    try names.map { name in
      let url = try validatedURL(for: name)
      return ProcessedPhoto(bytes: try Data(contentsOf: url), fileName: name)
    }
  }

  public func remove(_ names: [String]) throws {
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
}
