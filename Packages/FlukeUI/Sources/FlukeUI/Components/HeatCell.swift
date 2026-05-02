import SwiftUI

public struct HeatCell: View {
    public let normalizedX: CGFloat        // 0..1
    public let normalizedY: CGFloat        // 0..1
    public let widthRatio: CGFloat         // typically 0.018 (5km / 280km bbox width)
    public let heightRatio: CGFloat        // typically 0.018
    public let color: Color
    public let intensity: Double           // 0..1

    public init(
        x: CGFloat,
        y: CGFloat,
        widthRatio: CGFloat = 0.018,
        heightRatio: CGFloat = 0.018,
        color: Color,
        intensity: Double
    ) {
        self.normalizedX = x
        self.normalizedY = y
        self.widthRatio = widthRatio
        self.heightRatio = heightRatio
        self.color = color
        self.intensity = max(0, min(1, intensity))
    }

    public var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(color.opacity(0.05 + intensity * 0.40))
                .frame(
                    width: geo.size.width * widthRatio,
                    height: geo.size.height * heightRatio
                )
                .position(
                    x: geo.size.width * normalizedX,
                    y: geo.size.height * normalizedY
                )
        }
    }
}
