#if canImport(AppKit)
  import AppKit
  import SwiftUI
  import Testing

  @testable import FlukeFeatures

  @MainActor
  struct YouInteractionTests {
    @Test("You controls guarantee a 44 by 44 point hit target")
    func minimumHitTarget() {
      let view = Button("Action") {}
        .youMinimumHitTarget()
      let hostingView = NSHostingView(rootView: view)

      let size = hostingView.fittingSize

      #expect(size.width >= 44)
      #expect(size.height >= 44)
    }

    @Test("The reviewed You actions share the hit-target contract")
    func reviewedActions() {
      #expect(
        YouInteractiveControl.allCases == [
          .retry,
          .signOut,
          .deleteAccount,
          .reauthenticateDeletion,
          .about,
          .privacy,
          .support,
          .attribution,
        ]
      )
      #expect(YouInteractiveControl.allCases.allSatisfy { $0.minimumHitDimension == 44 })
    }

    @Test("Resource links stack at compact width with accessibility text")
    func resourceLinksAdaptToCompactAccessibilityLayout() {
      let view = YouResourceLinks()
        .environment(\.dynamicTypeSize, .accessibility3)
        .frame(width: 180)
      let hostingView = NSHostingView(rootView: view)

      let size = hostingView.fittingSize

      #expect(size.width <= 180)
      #expect(size.height >= 4 * 44)
    }
  }
#endif
