import SwiftUI
import XCTest
import SnapshotTesting
@testable import FlukeUI

final class DorsalFinShapeSnapshotTests: XCTestCase {

    func test_dorsalFinShape_atDefaultSize() {
        let view = VStack(content: {
            DorsalFinShape()
                .fill(Color.abyss)
                .frame(width: 64, height: 64)
                .padding(8)
        })
        .background(Color.bone)
        
        let hosting = NSHostingController(rootView: view)
        hosting.view.frame.size = CGSize(width: 80, height: 80)

        assertSnapshot(of: hosting.view, as: .image)
    }

    func test_dorsalFinShape_atSmallSize() {
        let view = VStack(content: {
            DorsalFinShape()
                .fill(Color.tide)
                .frame(width: 16, height: 16)
        })
        
        let hosting = NSHostingController(rootView: view)
        hosting.view.frame.size = CGSize(width: 16, height: 16)

        assertSnapshot(of: hosting.view, as: .image)
    }
}
