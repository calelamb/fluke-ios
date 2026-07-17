import SwiftUI
import XCTest
import SnapshotTesting
@testable import FlukeUI

@MainActor
final class SalishSeaShapeSnapshotTests: XCTestCase {

    func test_salishSeaShape_atTypicalSize() throws {
        let view = VStack(content: {
            SalishSeaShape()
                .stroke(Color.tide, lineWidth: 1)
                .frame(width: 320, height: 200)
        })
        .padding(8)
        .background(Color.fog)

        let image = try renderedSnapshot(view, size: CGSize(width: 336, height: 216))

        assertSnapshot(of: image, as: .image)
    }
}
