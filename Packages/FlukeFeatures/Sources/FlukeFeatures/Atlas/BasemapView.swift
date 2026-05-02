import SwiftUI
import FlukeKit
import FlukeUI

/// Hand-illustrated Salish Sea basemap shared by all Atlas sub-views.
/// Bathymetric tinting + coastline + named-feature labels.
public struct BasemapView: View {

    public init() {}

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                // Water base — mid-tide tint
                Rectangle()
                    .fill(Color.tide.opacity(0.10))

                // Coastline filled with land color, stroked with mist
                SalishSeaShape()
                    .fill(Color.bone)
                SalishSeaShape()
                    .stroke(Color.mist.opacity(0.7), lineWidth: 0.6)

                // Named-feature labels
                ForEach(SalishSeaShape.namedFeatures) { feature in
                    let p = projection.project(lat: feature.lat, lng: feature.lng)
                    Text(feature.name)
                        .font(.system(size: fontSize(for: feature.kind), design: .serif))
                        .italic()
                        .foregroundStyle(Color.abyss.opacity(opacity(for: feature.kind)))
                        .position(
                            x: CGFloat(p.x) * geo.size.width,
                            y: CGFloat(p.y) * geo.size.height
                        )
                }
            }
        }
        .background(Color.fog)
    }

    private let projection = SalishSeaProjection.salishSea

    private func fontSize(for kind: String) -> CGFloat {
        switch kind {
        case "land":   return 11
        case "strait", "canal", "sound": return 10
        case "pass", "inlet":            return 9
        case "point":                    return 8
        default:                         return 9
        }
    }

    private func opacity(for kind: String) -> Double {
        switch kind {
        case "land", "strait", "sound": return 0.7
        default:                        return 0.55
        }
    }
}
