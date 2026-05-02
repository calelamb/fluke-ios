import SwiftUI
import FlukeKit

public struct ConfidenceCone: View {
    public let cells: [PredictionCell]
    public let projection: SalishSeaProjection
    public let color: Color

    public init(cells: [PredictionCell], projection: SalishSeaProjection = .salishSea, color: Color = .ember) {
        self.cells = cells
        self.projection = projection
        self.color = color
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                    let p = projection.project(lat: cell.lat, lng: cell.lng)
                    Circle()
                        .fill(color.opacity(opacityFor(probability: cell.probability)))
                        .frame(width: 24, height: 24)
                        .position(
                            x: CGFloat(p.x) * geo.size.width,
                            y: CGFloat(p.y) * geo.size.height
                        )
                        .blur(radius: 2)
                }
            }
        }
    }

    private func opacityFor(probability: Double) -> Double {
        // Tier 1 (top 10% — highest probability): opacity 0.55
        // Tier 2 (next 20%): 0.30
        // Tier 3 (next 30%): 0.15
        // Drop the rest.
        guard let max = cells.map({ $0.probability }).max(), max > 0 else { return 0 }
        let normalized = probability / max
        if normalized >= 0.7 { return 0.55 }
        if normalized >= 0.4 { return 0.30 }
        if normalized >= 0.2 { return 0.15 }
        return 0
    }
}
