import SwiftUI

/// The canonical Fluke dorsal-fin glyph as a SwiftUI Shape.
///
/// Path is normalized to a 28×28 unit box and scaled to the rect provided
/// by SwiftUI. Mirrors the SVG path used on the web in
/// `apps/web/src/components/layout/MobileBottomNav.tsx` and
/// the map markers — `M10 24 L10 14 Q14 8 20 24 Z`.
public struct DorsalFinShape: Shape {

    public init() {}

    public func path(in rect: CGRect) -> Path {
        // Normalize to the 28-unit reference box and scale to rect.
        let s = min(rect.width, rect.height) / 28.0
        let x = rect.midX - (28.0 * s) / 2.0
        let y = rect.midY - (28.0 * s) / 2.0

        func point(_ px: CGFloat, _ py: CGFloat) -> CGPoint {
            CGPoint(x: x + px * s, y: y + py * s)
        }

        var path = Path()
        // M10 24
        path.move(to: point(10, 24))
        // L10 14
        path.addLine(to: point(10, 14))
        // Q14 8 20 24
        path.addQuadCurve(to: point(20, 24), control: point(14, 8))
        // Z
        path.closeSubpath()
        return path
    }
}

#Preview {
    VStack(spacing: 24) {
        DorsalFinShape().fill(Color.abyss).frame(width: 96, height: 96)
        DorsalFinShape().fill(Color.tide).frame(width: 28, height: 28)
        DorsalFinShape().fill(Color.ember).frame(width: 16, height: 16)
    }
    .padding()
    .background(Color.bone)
}
