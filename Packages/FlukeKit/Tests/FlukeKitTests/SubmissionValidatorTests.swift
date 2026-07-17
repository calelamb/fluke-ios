import Foundation
import FlukeReleaseB
import Testing

@Suite("Submission validation")
struct SubmissionValidatorTests {
  @Test("Submission rejects impossible coordinates and future observation dates")
  func invalidGeographyAndDate() {
    #expect(throws: SubmissionValidationError.latitude) {
      try SubmissionValidator.validate(.fixture(latitude: 91))
    }
    #expect(throws: SubmissionValidationError.longitude) {
      try SubmissionValidator.validate(.fixture(longitude: -181))
    }
    #expect(throws: SubmissionValidationError.observedAt) {
      try SubmissionValidator.validate(.fixture(observedAt: Date().addingTimeInterval(301)))
    }
  }

  @Test("Anonymous submission requires a valid bounded email")
  func anonymousEmail() {
    #expect(throws: SubmissionValidationError.email) {
      try SubmissionValidator.validate(.fixture(observerEmail: nil))
    }
    #expect(throws: SubmissionValidationError.email) {
      try SubmissionValidator.validate(.fixture(observerEmail: "not-an-email"))
    }
    #expect(throws: SubmissionValidationError.email) {
      try SubmissionValidator.validate(.fixture(observerEmail: String(repeating: "a", count: 245) + "@x.com"))
    }
  }

  @Test("Submission validates bounded group, text, and photo counts")
  func boundedFields() throws {
    #expect(throws: SubmissionValidationError.groupSize) {
      try SubmissionValidator.validate(.fixture(groupSize: 0))
    }
    #expect(throws: SubmissionValidationError.notes) {
      try SubmissionValidator.validate(.fixture(notes: String(repeating: "n", count: 2_001)))
    }
    #expect(throws: SubmissionValidationError.locationName) {
      try SubmissionValidator.validate(.fixture(locationName: String(repeating: "l", count: 201)))
    }
    #expect(throws: SubmissionValidationError.photos) {
      try SubmissionValidator.validate(.fixture(photoCount: 6))
    }
    let payload = try SubmissionValidator.validate(.fixture(groupSize: 100, photoCount: 1))
    #expect(payload.groupSize == 100)
    #expect(throws: SubmissionValidationError.groupSize) {
      try SubmissionValidator.validate(.fixture(groupSize: 101))
    }
  }
}

extension SubmissionDraft {
  static func fixture(
    latitude: Double = 48.515,
    longitude: Double = -123.152,
    observedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
    groupSize: Int = 3,
    notes: String? = "Traveling north",
    locationName: String? = "Lime Kiln",
    observerEmail: String? = "observer@example.com",
    photoCount: Int = 1
  ) -> SubmissionDraft {
    SubmissionDraft(
      latitude: latitude,
      longitude: longitude,
      observedAt: observedAt,
      groupSize: groupSize,
      notes: notes,
      locationName: locationName,
      observerEmail: observerEmail,
      photoCount: photoCount
    )
  }
}
