import FlukeKit
import Foundation

public protocol SubmissionServiceProtocol: Sendable {
  func submit(payload: SubmissionPayload, photos: [ProcessedPhoto]) async throws -> SubmissionReceipt
}

public enum SubmissionServiceError: Error, Equatable, Sendable {
  case invalidPhotos
  case partial(receipt: SubmissionReceipt, failedPhotoIndices: [Int])
}

public struct SubmissionService: SubmissionServiceProtocol, Sendable {
  private let api: APIClient

  public init(api: APIClient) { self.api = api }

  public func submit(
    payload: SubmissionPayload,
    photos: [ProcessedPhoto]
  ) async throws -> SubmissionReceipt {
    guard !photos.isEmpty, photos.count <= 5,
      photos.allSatisfy({ $0.bytes.count <= 10 * 1_024 * 1_024 && $0.mimeType == "image/jpeg" })
    else { throw SubmissionServiceError.invalidPhotos }

    let receipt: SubmissionReceipt
    if let existingReceipt = payload.existingReceipt {
      receipt = existingReceipt
    } else {
      receipt = try await api.post(
        APIRequest(path: "/api/v1/sightings"),
        body: payload,
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
          headers: ["x-photo-upload-token": receipt.photoUploadToken]
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
