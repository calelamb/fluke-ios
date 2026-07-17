import Testing

@testable import FlukeFeatures

@MainActor
struct SightingDetailNavigationTests {
    @Test("Movement routing stages the catalog ID before dismissing sighting detail")
    func stagesBeforeDismissing() {
        var events: [String] = []

        SightingDetailNavigation.openMovement(
            catalogID: "J35",
            stage: { events.append("stage:\($0)") },
            dismiss: { events.append("dismiss") }
        )

        #expect(events == ["stage:J35", "dismiss"])
    }

    @Test("A sighting movement route waits for sheet dismissal before opening its cover")
    func waitsForSheetDismissal() {
        let router = SightingMovementPresentationRouter()
        var opened: [String] = []

        router.request(catalogID: "J35")
        #expect(opened.isEmpty)

        router.detailDidDismiss { opened.append($0) }

        #expect(opened == ["J35"])
        #expect(router.pendingCatalogID == nil)
    }

    @Test("A sparse profile route waits for movement dismissal before opening Submit")
    func waitsForMovementDismissal() {
        let router = WhaleMovementSubmitRouter()
        var submitCount = 0

        router.requestSubmit()
        #expect(submitCount == 0)

        router.movementDidDismiss { submitCount += 1 }

        #expect(submitCount == 1)
        #expect(!router.isSubmitPending)
    }

    @Test("Sparse movement stages Submit before asking its cover to dismiss")
    func sparseMovementStagesBeforeDismissal() {
        var events: [String] = []

        MovementTrackNavigation.submit(
            stage: { events.append("stage") },
            dismiss: { events.append("dismiss") }
        )

        #expect(events == ["stage", "dismiss"])
    }
}
