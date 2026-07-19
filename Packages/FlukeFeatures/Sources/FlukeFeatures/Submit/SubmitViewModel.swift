import FlukeKit
import FlukeReleaseB
import Foundation
import Observation

@MainActor
@Observable
public final class SubmitViewModel {
  public enum State: Equatable, Sendable {
    case editing
    case submitting
    case queued
    case success
    case partial
    case validation(SubmissionValidationError)
    case failed(String)
  }

  public enum Dismissal: Equatable, Sendable { case allowed, requiresConfirmation }

  public var latitude: Double
  public var longitude: Double
  public var observedAt: Date
  public var groupSize = 1
  public var notes = ""
  public var locationName = ""
  public var email = ""
  public var photos: [ProcessedPhoto] = []
  public private(set) var state = State.editing
  public private(set) var photoErrorMessage: String?
  public private(set) var validationField: SubmissionFormField?

  private let service: any SubmissionServiceProtocol
  private let queue: any SubmissionQueueProtocol
  private let isSignedIn: Bool
  private let signedInObserverEmail: String?
  private let submissionsEnabled: Bool
  private let clientSubmissionID: UUID
  private let ecotypeGuess: Ecotype?
  private let localIdentification: LocalIdentificationSuggestion?
  private let invalidator: any SubmissionInvalidating
  private var hasInvalidatedDefinitiveSuccess = false
  private let initialLatitude: Double
  private let initialLongitude: Double
  private let initialObservedAt: Date

  public init(
    service: any SubmissionServiceProtocol,
    queue: any SubmissionQueueProtocol,
    isSignedIn: Bool = false,
    signedInObserverEmail: String? = nil,
    submissionsEnabled: Bool = true,
    clientSubmissionID: UUID = UUID(),
    ecotypeGuess: Ecotype? = nil,
    localIdentification: LocalIdentificationSuggestion? = nil,
    invalidator: any SubmissionInvalidating = NoopSubmissionInvalidator(),
    latitude: Double = 48.52,
    longitude: Double = -123.15,
    observedAt: Date = Date()
  ) {
    self.service = service
    self.queue = queue
    self.isSignedIn = isSignedIn
    self.signedInObserverEmail = signedInObserverEmail
    self.submissionsEnabled = submissionsEnabled
    self.clientSubmissionID = clientSubmissionID
    self.ecotypeGuess = ecotypeGuess
    self.localIdentification = localIdentification
    self.invalidator = invalidator
    self.latitude = latitude
    self.longitude = longitude
    self.observedAt = observedAt
    initialLatitude = latitude
    initialLongitude = longitude
    initialObservedAt = observedAt
  }

  public var dismissal: Dismissal {
    isTerminal || !isDirty ? .allowed : .requiresConfirmation
  }

  public var showsObserverEmail: Bool { !isSignedIn || signedInObserverEmail == nil }

  public var disabledMessage: String? {
    submissionsEnabled ? nil : "Sighting submissions are temporarily unavailable."
  }

  public var failureMessage: String? {
    guard case .failed(let message) = state else { return nil }
    return message
  }

  public func addPhotos(_ additions: [ProcessedPhoto]) {
    photos = Array(
      (photos + additions).reduce([ProcessedPhoto]()) { unique, photo in
        guard
          !unique.contains(where: {
            $0.idempotencyID == photo.idempotencyID || $0.bytes == photo.bytes
          })
        else { return unique }
        return unique + [photo]
      }.prefix(5))
    photoErrorMessage = nil
  }

  public func reportPhotoFailure(_ failure: PhotoSelectionFailure) {
    photoErrorMessage = PhotoSelectionPresentation.message(for: failure)
  }

  public func submit() async {
    guard submissionsEnabled, state != .submitting, state != .queued, state != .success else {
      return
    }
    validationField = nil
    let payload: SubmissionPayload
    do {
      payload = try SubmissionValidator.validate(
        SubmissionDraft(
          latitude: latitude, longitude: longitude, observedAt: observedAt,
          groupSize: groupSize, notes: notes, locationName: locationName,
          observerEmail: showsObserverEmail ? email : signedInObserverEmail,
          photoCount: photos.count,
          clientSubmissionID: clientSubmissionID, ecotypeGuess: ecotypeGuess,
          localIdentification: localIdentification
        ))
    } catch let error as SubmissionValidationError {
      state = .validation(error)
      validationField = SubmissionFormField.forValidationError(error)
      return
    } catch {
      state = .failed("Check the sighting details and try again.")
      return
    }

    state = .submitting
    do {
      _ = try await service.submit(payload: payload, photos: photos)
      state = .success
      await invalidateDefinitiveSuccessOnce()
    } catch SubmissionServiceError.partial(let receipt, let indices) {
      await invalidateDefinitiveSuccessOnce()
      let remaining = indices.compactMap { photos.indices.contains($0) ? photos[$0] : nil }
      do {
        _ = try await queue.enqueue(payload: payload.resuming(receipt: receipt), photos: remaining)
        state = .partial
      } catch {
        state = .failed("The sighting was saved, but failed photos could not be queued.")
      }
    } catch APIError.offline {
      do {
        _ = try await queue.enqueue(payload: payload, photos: photos)
        state = .queued
      } catch {
        state = .failed("Fluke couldn't safely queue this sighting.")
      }
    } catch {
      state = .failed("Fluke couldn't submit this sighting. Please try again.")
    }
  }

  private func invalidateDefinitiveSuccessOnce() async {
    guard !hasInvalidatedDefinitiveSuccess else { return }
    hasInvalidatedDefinitiveSuccess = true
    await invalidator.ownerSightingsDidChange()
  }

  private var isDirty: Bool {
    latitude != initialLatitude || longitude != initialLongitude || observedAt != initialObservedAt
      || !locationName.isEmpty || !notes.isEmpty || !email.isEmpty || !photos.isEmpty
      || groupSize != 1
  }

  private var isTerminal: Bool {
    switch state {
    case .queued, .success, .partial: true
    default: false
    }
  }
}
