import Testing

@testable import FlukeFeatures

@MainActor
struct SightingDetailNavigationTests {
    @Test("Movement routing dismisses sighting detail before forwarding its catalog ID")
    func dismissesBeforeForwarding() {
        var events: [String] = []

        SightingDetailNavigation.openMovement(
            catalogID: "J35",
            dismiss: { events.append("dismiss") },
            open: { events.append("open:\($0)") }
        )

        #expect(events == ["dismiss", "open:J35"])
    }
}
