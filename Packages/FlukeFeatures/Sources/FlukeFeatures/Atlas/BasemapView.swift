import FlukeKit
import FlukeUI
import SwiftUI

/// Hand-illustrated Salish Sea basemap shared by all Atlas sub-views.
/// Bathymetric tinting + coastline + named-feature labels.
public struct BasemapView: View {

  public init() {}

  public var body: some View {
    GeometryReader { geo in
      ZStack {
        Rectangle()
          .fill(Color.tide.opacity(0.10))

        bathymetricBands(size: geo.size)

        // Coastline filled with land color, stroked with mist
        SalishSeaShape()
          .fill(Color.bone)
        SalishSeaShape()
          .stroke(Color.mist.opacity(0.7), lineWidth: 0.6)

        // Named-feature labels
        ForEach(SalishSeaShape.namedFeatures) { feature in
          let p = projection.project(lat: feature.lat, lng: feature.lng)
          Text(feature.name)
            .font(.custom("Fraunces", size: fontSize(for: feature.kind), relativeTo: .caption))
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
    .accessibilityHidden(true)
  }

  private let projection = AtlasProjection.bounds

  private func bathymetricBands(size: CGSize) -> some View {
    ZStack {
      Ellipse()
        .fill(Color.deep.opacity(0.045))
        .frame(width: size.width * 0.72, height: size.height * 0.56)
        .offset(x: -size.width * 0.13, y: -size.height * 0.06)
      Ellipse()
        .stroke(Color.tide.opacity(0.08), lineWidth: max(size.width * 0.08, 24))
        .frame(width: size.width * 0.48, height: size.height * 0.7)
        .offset(x: size.width * 0.18, y: size.height * 0.15)
      Ellipse()
        .fill(Color.abyss.opacity(0.035))
        .frame(width: size.width * 0.25, height: size.height * 0.38)
        .offset(x: -size.width * 0.25, y: size.height * 0.24)
    }
    .clipped()
  }

  private func fontSize(for kind: String) -> CGFloat {
    switch kind {
    case "land": return 11
    case "strait", "canal", "sound": return 10
    case "pass", "inlet": return 9
    case "point": return 8
    default: return 9
    }
  }

  private func opacity(for kind: String) -> Double {
    switch kind {
    case "land", "strait", "sound": return 0.7
    default: return 0.55
    }
  }
}
