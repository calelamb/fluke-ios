import Testing

@testable import Fluke

struct SubmissionAccessibilityTests {
  @Test("Queue flush announces only confirmed completed uploads")
  func queueFlushAnnouncement() {
    #expect(
      SubmissionFlushAnnouncement.message(before: 3, after: 1) == "2 queued sightings uploaded")
    #expect(
      SubmissionFlushAnnouncement.message(before: 1, after: 0) == "1 queued sighting uploaded")
    #expect(SubmissionFlushAnnouncement.message(before: 1, after: 1) == nil)
    #expect(SubmissionFlushAnnouncement.message(before: 0, after: 0) == nil)
    #expect(SubmissionFlushAnnouncement.message(before: 1, after: 2) == nil)
  }
}
