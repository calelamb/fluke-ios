import FlukeKit
import Foundation

public protocol SubmissionServiceProtocol: Sendable {
  func submit(payload: SubmissionPayload, photos: [ProcessedPhoto]) async throws -> SubmissionReceipt
}

public enum SubmissionServiceError: Error, Equatable, Sendable {
  case invalidPhotos
  case missingObserverEmail
  case partial(receipt: SubmissionReceipt, failedPhotoIndices: [Int])
}

public enum SubmissionUploadLimits {
  /// Leaves room for the maximum legal filename, MIME and multipart framing.
  public static let multipartReservedBytes = 2_048
  public static let maximumProcessedPhotoBytes =
    MutationBodyLimits.maximumBytes - multipartReservedBytes
}

public struct SubmissionService: SubmissionServiceProtocol, Sendable {
  /// Photo POSTs use `Idempotency-Key: <clientSubmissionId>:<photoIdempotencyUUID>`.
  /// The API photo route must deduplicate this key within the parent sighting.
  private let api: APIClient

  public init(api: APIClient) { self.api = api }

  public func submit(
    payload: SubmissionPayload,
    photos: [ProcessedPhoto]
  ) async throws -> SubmissionReceipt {
    guard !photos.isEmpty, photos.count <= 5,
      photos.allSatisfy({
        $0.bytes.count <= SubmissionUploadLimits.maximumProcessedPhotoBytes
          && $0.mimeType == "image/jpeg"
      })
    else { throw SubmissionServiceError.invalidPhotos }

    let receipt: SubmissionReceipt
    if let existingReceipt = payload.existingReceipt {
      receipt = existingReceipt
    } else {
      guard let request = SubmitSightingRequest(payload: payload) else {
        throw SubmissionServiceError.missingObserverEmail
      }
      receipt = try await api.post(
        APIRequest(path: "/api/v1/sightings"),
        body: request,
        headers: ["Idempotency-Key": payload.clientSubmissionID.uuidString]
      )
    }

    var failedIndices: [Int] = []
    for (index, photo) in photos.enumerated() {
      do {
        let part = try MultipartPart.data(
          name: "photo", fileName: photo.fileName, mimeType: photo.mimeType, bytes: photo.bytes
        )
        let _: EmptySubmissionResponse = try await api.postMultipart(
          APIRequest(path: "/api/v1/sightings/\(receipt.id)/photos"),
          parts: [part],
          headers: [
            "x-photo-upload-token": receipt.photoUploadToken,
            "Idempotency-Key": "\(payload.clientSubmissionID.uuidString):\(photo.idempotencyID.uuidString)",
          ]
        )
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        failedIndices.append(index)
      }
    }
    guard failedIndices.isEmpty else {
      throw SubmissionServiceError.partial(receipt: receipt, failedPhotoIndices: failedIndices)
    }
    return receipt
  }
}

private struct EmptySubmissionResponse: Decodable, Sendable {}

/// Exact wire DTO for `SubmitSightingPayloadSchema`. Queue-only receipt and
/// photo-count fields must never cross this boundary.
private struct SubmitSightingRequest: Encodable, Sendable {
  let clientSubmissionId: UUID
  let observedAt: String
  let latitude: Double
  let longitude: Double
  let locationName: String?
  let groupSize: Int?
  let behaviorNotes: String?
  let observerEmail: String

  init?(payload: SubmissionPayload) {
    guard let observerEmail = payload.observerEmail else { return nil }
    clientSubmissionId = payload.clientSubmissionID
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    observedAt = formatter.string(from: payload.observedAt)
    latitude = payload.latitude
    longitude = payload.longitude
    locationName = payload.locationName
    groupSize = payload.groupSize
    behaviorNotes = payload.notes
    self.observerEmail = observerEmail
  }
}
