import SwiftUI
import XCTest
import SnapshotTesting
@testable import FlukeUI

final class SalishSeaShapeSnapshotTests: XCTestCase {

    func test_salishSeaShape_atTypicalSize() {
        let view = VStack(content: {
            SalishSeaShape()
                .stroke(Color.tide, lineWidth: 1)
                .frame(width: 320, height: 200)
        })
        .padding(8)
        .background(Color.fog)

        let hosting = NSHostingController(rootView: view)
        hosting.view.frame.size = CGSize(width: 336, height: 232)

        assertSnapshot(of: hosting.view, as: .image)
    }
}
