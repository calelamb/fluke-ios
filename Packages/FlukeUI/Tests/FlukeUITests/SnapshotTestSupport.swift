import AppKit
import SnapshotTesting
import SwiftUI
import XCTest

/// Preserves geometry checks while allowing bounded macOS renderer anti-aliasing drift.
///
/// GitHub-hosted runners differed from the checked-in references by at most 0.42%
/// of pixels and four channel values. Snapshot dimensions must still match exactly.
let releaseImageSnapshot = Snapshotting<NSImage, NSImage>.image(
    precision: 0.99,
    perceptualPrecision: 0.98
)

@MainActor
func renderedSnapshot<V: View>(
    _ view: V,
    size: CGSize,
    scale: CGFloat = 2
) throws -> NSImage {
    let renderer = ImageRenderer(content: view)
    renderer.proposedSize = ProposedViewSize(size)
    renderer.scale = scale

    return try XCTUnwrap(
        renderer.nsImage,
        "SwiftUI failed to render the snapshot image"
    )
}
