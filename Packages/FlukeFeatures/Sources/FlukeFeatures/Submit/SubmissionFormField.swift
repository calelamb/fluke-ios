import FlukeReleaseB

public enum SubmissionFormField: Hashable, Sendable {
  case location
  case locationName
  case observedAt
  case groupSize
  case email
  case notes
  case photos

  public static func forValidationError(_ error: SubmissionValidationError) -> Self {
    switch error {
    case .latitude, .longitude: .location
    case .observedAt: .observedAt
    case .groupSize: .groupSize
    case .notes: .notes
    case .locationName: .locationName
    case .email: .email
    case .photos: .photos
    }
  }

  var acceptsKeyboardFocus: Bool {
    switch self {
    case .locationName, .email, .notes: true
    default: false
    }
  }
}
