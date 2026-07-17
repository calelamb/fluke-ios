import SnapshotTesting
import SwiftUI
import XCTest

@testable import FlukeUI

@MainActor
final class LaunchComponentSnapshotTests: XCTestCase {
    override func setUp() async throws {
        FlukeUIFontRegistration.registerIfNeeded()
    }

    func test_standardText() throws {
        try assertGallery(named: "standard", gallery: componentGallery())
    }

    func test_accessibilityXXXL() throws {
        try assertGallery(
            named: "accessibility-xxxl",
            gallery: componentGallery().environment(\.dynamicTypeSize, .accessibility5),
            height: 980
        )
    }

    func test_increasedContrast() throws {
        try assertGallery(
            named: "increased-contrast",
            gallery: componentGallery().flukeContrast(.increased)
        )
    }

    func test_reduceMotion() throws {
        try assertGallery(
            named: "reduce-motion",
            gallery: componentGallery(reduceMotion: true)
        )
    }

    private func componentGallery(reduceMotion: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            EditorialHeading(level: .section, text: "Salish Sea field notes")

            Button("Add sighting") {}
                .buttonStyle(FlukeButtonStyle.primary)

            Button("Add sighting") {}
                .buttonStyle(FlukeButtonStyle.primary)
                .disabled(true)

            Button("Browse whales") {}
                .buttonStyle(FlukeButtonStyle.secondary)

            HStack {
                EcotypeBadge(label: "Resident", color: .tide)
                EcotypeBadge(label: "Bigg's", color: .ember)
                EcotypeBadge(label: "Offshore", color: .deep)
                EcotypeBadge(label: "Unknown", color: .mist)
            }

            FlukeCard {
                Text("J pod was reported west of San Juan Island.")
                    .font(.flukeBody)
            }

            FlukeEmptyState(
                title: "No sightings yet",
                message: "Try another date or browse the whale catalog."
            )
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.fog)
        .flukeMotion(.flukeBase, reduceMotion: reduceMotion)
    }

    private func assertGallery<Gallery: View>(
        named name: String,
        gallery: Gallery,
        height: CGFloat = 760
    ) throws {
        let image = try renderedSnapshot(
            gallery
                .frame(width: 430, height: height, alignment: .topLeading)
                .background(Color.fog),
            size: CGSize(width: 430, height: height)
        )
        assertSnapshot(of: image, as: releaseImageSnapshot, named: name)
    }
}
