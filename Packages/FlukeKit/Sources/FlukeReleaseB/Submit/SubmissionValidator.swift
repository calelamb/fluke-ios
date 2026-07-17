import Foundation

public enum SubmissionValidationError: Error, Equatable, Sendable {
  case latitude
  case longitude
  case observedAt
  case groupSize
  case notes
  case locationName
  case email
  case photos
}

public enum SubmissionValidator {
  public static func validate(
    _ draft: SubmissionDraft,
    now: Date = Date(),
    requiresObserverEmail: Bool = true
  ) throws -> SubmissionPayload {
    guard (-90...90).contains(draft.latitude) else { throw SubmissionValidationError.latitude }
    guard (-180...180).contains(draft.longitude) else { throw SubmissionValidationError.longitude }
    guard draft.observedAt <= now.addingTimeInterval(300) else {
      throw SubmissionValidationError.observedAt
    }
    guard (1...100).contains(draft.groupSize) else { throw SubmissionValidationError.groupSize }
    guard bounded(draft.notes, maximum: 2_000) else { throw SubmissionValidationError.notes }
    guard bounded(draft.locationName, maximum: 200) else {
      throw SubmissionValidationError.locationName
    }
    let email = normalized(draft.observerEmail)
    if requiresObserverEmail && email == nil { throw SubmissionValidationError.email }
    if let email {
      guard email.count <= 254, EmailAddressValidator.isValid(email) else {
        throw SubmissionValidationError.email
      }
    }
    guard (1...5).contains(draft.photoCount) else { throw SubmissionValidationError.photos }

    return SubmissionPayload(
      latitude: draft.latitude,
      longitude: draft.longitude,
      observedAt: draft.observedAt,
      groupSize: draft.groupSize,
      notes: normalized(draft.notes),
      locationName: normalized(draft.locationName),
      observerEmail: email,
      photoCount: draft.photoCount
    )
  }

  private static func bounded(_ value: String?, maximum: Int) -> Bool {
    guard let value else { return true }
    return value.count <= maximum
  }

  private static func normalized(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
