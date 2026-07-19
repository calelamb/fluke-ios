import AppKit
import FlukeML
import FlukeUI
import SwiftUI
import Testing

@testable import FlukeFeatures

@MainActor
@Suite("Identify feature rendering")
struct IdentifyFeatureRenderingTests {
  @Test("disabled feature renders its honest unavailable state")
  func disabledStateRenders() throws {
    let view = IdentifyView(
      capability: .disabled,
      browseWhales: {},
      openWhale: { _ in },
      submitSighting: {}
    )

    #expect(try render(view) != nil)
  }

  @Test("ready feature renders live-camera controls")
  func readyStateRenders() throws {
    let view = IdentifyView(
      capability: .onDevice(RenderingIdentifier()),
      browseWhales: {},
      openWhale: { _ in },
      submitSighting: {}
    )

    #expect(try render(view) != nil)
  }

  @Test(
    "unknown, poor-quality, unavailable, and neutral presentations render",
    arguments: [
      IdentifyPresentation.idle,
      .analyzing,
      .provisional,
      .stabilized,
      .unknown,
      .poorQuality,
      .unavailable,
    ]
  )
  func presentationRenders(_ presentation: IdentifyPresentation) throws {
    let view = IdentifyResultContent(
      result: nil,
      presentation: presentation,
      disclaimer: "Uncalibrated visual similarity",
      openWhale: { _ in }
    )

    let expectsVisibleContent: Bool = switch presentation {
    case .unknown, .poorQuality, .unavailable: true
    default: false
    }
    #expect((try render(view) != nil) == expectsVisibleContent)
  }

  @Test("results render stabilized and provisional matches with artifact provenance")
  func resultsRender() throws {
    let result = IdentifyResult(
      provisional: [
        IdentifyResultMatch(
          whaleID: "whale-j35",
          catalogID: "J35",
          score: 0.812,
          rank: 1,
          referencePhotoIDs: ["reference-1", "reference-2"]
        )
      ],
      prominent: IdentifyResultMatch(
        whaleID: "whale-j35",
        catalogID: "J35",
        score: 0.934,
        rank: 1,
        referencePhotoIDs: ["reference-1"]
      ),
      artifact: LocalIdentificationArtifact(
        manifestVersion: "manifest-v1",
        modelVersion: "model-v1",
        indexVersion: "index-v1"
      )
    )
    let view = IdentifyResultsView(
      result: result,
      disclaimer: "Uncalibrated visual similarity",
      openWhale: { _ in }
    )
    .frame(width: 430, height: 700)

    #expect(try render(view) != nil)
  }

  private func render<Content: View>(_ content: Content) throws -> NSImage? {
    FlukeUIFontRegistration.registerIfNeeded()
    let renderer = ImageRenderer(content: content)
    renderer.proposedSize = ProposedViewSize(width: 430, height: 700)
    renderer.scale = 1
    return renderer.nsImage
  }
}

private struct RenderingIdentifier: LocalIdentifying {
  func identify(frame: CameraFrame) async throws -> LocalIdentificationState {
    throw CancellationError()
  }
}
