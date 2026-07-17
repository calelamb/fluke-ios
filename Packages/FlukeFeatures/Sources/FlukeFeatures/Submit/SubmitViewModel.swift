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

  public var latitude = 48.52
  public var longitude = -123.15
  public var observedAt = Date()
  public var groupSize = 1
  public var notes = ""
  public var locationName = ""
  public var email = ""
  public var photos: [ProcessedPhoto] = []
  public private(set) var state = State.editing
  public private(set) var photoErrorMessage: String?

  private let service: any SubmissionServiceProtocol
  private let queue: any SubmissionQueueProtocol
  private let isSignedIn: Bool
  private let submissionsEnabled: Bool

  public init(
    service: any SubmissionServiceProtocol,
    queue: any SubmissionQueueProtocol,
    isSignedIn: Bool = false,
    submissionsEnabled: Bool = true
  ) {
    self.service = service
    self.queue = queue
    self.isSignedIn = isSignedIn
    self.submissionsEnabled = submissionsEnabled
  }

  public var dismissal: Dismissal {
    isTerminal || !isDirty ? .allowed : .requiresConfirmation
  }

  public var showsObserverEmail: Bool { !isSignedIn }

  public var disabledMessage: String? {
    submissionsEnabled ? nil : "Sighting submissions are temporarily unavailable."
  }

  public func addPhotos(_ additions: [ProcessedPhoto]) {
    photos = Array((photos + additions).prefix(5))
    photoErrorMessage = nil
  }

  public func reportPhotoFailure(_ failure: PhotoSelectionFailure) {
    photoErrorMessage = PhotoSelectionPresentation.message(for: failure)
  }

  public func submit() async {
    guard submissionsEnabled, state != .submitting, state != .queued, state != .success else { return }
    let payload: SubmissionPayload
    do {
      payload = try SubmissionValidator.validate(SubmissionDraft(
        latitude: latitude, longitude: longitude, observedAt: observedAt,
        groupSize: groupSize, notes: notes, locationName: locationName,
        observerEmail: isSignedIn ? nil : email, photoCount: photos.count
      ), requiresObserverEmail: !isSignedIn)
    } catch let error as SubmissionValidationError {
      state = .validation(error)
      return
    } catch {
      state = .failed("Check the sighting details and try again.")
      return
    }

    state = .submitting
    do {
      _ = try await service.submit(payload: payload, photos: photos)
      state = .success
    } catch SubmissionServiceError.partial(let receipt, let indices) {
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

  private var isDirty: Bool {
    !locationName.isEmpty || !notes.isEmpty || !email.isEmpty || !photos.isEmpty || groupSize != 1
  }

  private var isTerminal: Bool {
    switch state {
    case .queued, .success, .partial: true
    default: false
    }
  }
}
