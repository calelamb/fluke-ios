import FlukeReleaseB
import Testing

@Suite("Submission invalidation hub")
struct SubmissionInvalidationHubTests {
  @Test("Typed subscribers receive the newest monotonically increasing owner-logbook revision")
  func revisions() async throws {
    let hub = SubmissionInvalidationHub()
    let updates = await hub.updates()
    await hub.ownerSightingsDidChange()
    await hub.ownerSightingsDidChange()
    let update = await updates.first(where: { _ in true })

    #expect(update?.revision == 2)
  }
}
