import FlukeKit
import FlukeUI
import SwiftUI

extension Ecotype {
    var flukeDisplayName: String {
        switch self {
        case .resident: "Resident"
        case .biggs: "Bigg's"
        case .offshore: "Offshore"
        case .unknown: "Unknown"
        }
    }

    var flukeColor: Color {
        switch self {
        case .resident: .tide
        case .biggs: .ember
        case .offshore: .deep
        case .unknown: .mist
        }
    }
}
