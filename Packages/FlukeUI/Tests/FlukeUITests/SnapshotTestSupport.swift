import AppKit
import SwiftUI
import XCTest

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
