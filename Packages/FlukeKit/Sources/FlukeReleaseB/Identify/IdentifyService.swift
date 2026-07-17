import FlukeKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum IdentifyPhotoError: Error, Equatable, Sendable {
  case unsupportedFormat
  case inputTooLarge
  case decompressionLimit
}

public struct IdentifyPhoto: Equatable, Sendable {
  public static let maximumBytes = MutationBodyLimits.maximumBytes - 2_048
  public static let maximumDecodedPixels = 40_000_000

  public let bytes: Data

  public init(bytes: Data) throws {
    guard !bytes.isEmpty, bytes.count <= Self.maximumBytes else {
      throw bytes.isEmpty ? IdentifyPhotoError.unsupportedFormat : IdentifyPhotoError.inputTooLarge
    }
    guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
      CGImageSourceGetType(source) == UTType.jpeg.identifier as CFString,
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int,
      width > 0, height > 0
    else { throw IdentifyPhotoError.unsupportedFormat }
    let (pixels, overflow) = width.multipliedReportingOverflow(by: height)
    guard !overflow, pixels <= Self.maximumDecodedPixels else {
      throw IdentifyPhotoError.decompressionLimit
    }
    self.bytes = bytes
  }
}

public protocol IdentifyServiceProtocol: Sendable {
  func identify(photo: IdentifyPhoto) async throws -> IdentifyResponse
}

public enum IdentifyServiceError: Error, Equatable, Sendable {
  case training
  case invalidResponse
}

public struct IdentifyService: IdentifyServiceProtocol, Sendable {
  private let api: APIClient

  public init(api: APIClient) { self.api = api }

  public func identify(photo: IdentifyPhoto) async throws -> IdentifyResponse {
    let part = try MultipartPart.data(
      name: "photo",
      fileName: "identification.jpg",
      mimeType: "image/jpeg",
      bytes: photo.bytes
    )
    do {
      // Keep this upload single-attempt until the API accepts a client idempotency key.
      // Once that contract exists, send the key and opt into `.transientOnce` safely.
      let response: IdentifyResponse = try await api.postMultipart(
        APIRequest(path: ReleaseBEndpoint.identify),
        parts: [part],
        retryPolicy: .never
      )
      return try validated(response)
    } catch is CancellationError {
      throw CancellationError()
    } catch APIError.remote(let status, _, _, _, _) where status == 501 {
      throw IdentifyServiceError.training
    }
  }

  private func validated(_ response: IdentifyResponse) throws -> IdentifyResponse {
    guard isBounded(response.model, maximum: 120),
      isBounded(response.indexVersion, maximum: 120),
      response.matches.count <= 100,
      response.matches.allSatisfy(isValid),
      response.uploadURL.map(isValidHTTPSURL) ?? true
    else { throw IdentifyServiceError.invalidResponse }

    let ordered = response.matches.enumerated()
      .sorted { lhs, rhs in
        if lhs.element.score != rhs.element.score {
          return lhs.element.score > rhs.element.score
        }
        if lhs.element.rank != rhs.element.rank {
          return lhs.element.rank < rhs.element.rank
        }
        return lhs.offset < rhs.offset
      }
      .prefix(3)
    return IdentifyResponse(
      matches: ordered.map(\.element),
      confidenceBand: response.confidenceBand,
      model: response.model,
      indexVersion: response.indexVersion,
      uploadURL: response.uploadURL
    )
  }

  private func isValid(_ match: IdentifyMatch) -> Bool {
    match.score.isFinite && (0...1).contains(match.score)
      && match.rank > 0 && match.rank <= 100
      && isBounded(match.catalogId, maximum: 120)
      && match.name.map { isBounded($0, maximum: 200) } ?? true
      && isBounded(match.explanation, maximum: 1_000)
      && match.matchedReferencePhotoIds.count <= 100
      && match.matchedReferencePhotoIds.allSatisfy { isBounded($0, maximum: 200) }
  }

  private func isBounded(_ value: String, maximum: Int) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return !trimmed.isEmpty && trimmed == value && value.count <= maximum
      && value.unicodeScalars.allSatisfy {
        !CharacterSet.controlCharacters.contains($0)
      }
  }

  private func isValidHTTPSURL(_ value: String) -> Bool {
    guard value.count <= 2_048, let components = URLComponents(string: value) else { return false }
    return components.scheme?.lowercased() == "https"
      && components.host?.isEmpty == false
      && components.user == nil
      && components.password == nil
      && components.fragment == nil
      && components.url?.absoluteString == value
  }
}
