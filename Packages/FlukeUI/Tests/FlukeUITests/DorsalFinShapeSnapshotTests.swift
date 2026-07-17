import SwiftUI
import XCTest
import SnapshotTesting
@testable import FlukeUI

@MainActor
final class DorsalFinShapeSnapshotTests: XCTestCase {

    func test_dorsalFinShape_atDefaultSize() throws {
        let view = VStack(content: {
            DorsalFinShape()
                .fill(Color.abyss)
                .frame(width: 64, height: 64)
                .padding(8)
        })
        .background(Color.bone)
        
        let image = try renderedSnapshot(view, size: CGSize(width: 80, height: 80))

        assertSnapshot(of: image, as: .image)
    }

    func test_dorsalFinShape_atSmallSize() throws {
        let view = VStack(content: {
            DorsalFinShape()
                .fill(Color.tide)
                .frame(width: 16, height: 16)
        })
        
        let image = try renderedSnapshot(view, size: CGSize(width: 16, height: 16))

        assertSnapshot(of: image, as: .image)
    }
}
