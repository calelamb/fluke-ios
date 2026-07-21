import FlukeKit
import FlukeUI
import SwiftUI

public struct AnimatedPolylineLayer: View {

  public let coordinates: [(lat: Double, lng: Double)]
  public let projection: SalishSeaProjection
  public let color: Color
  public let drawDuration: Double
  public let isLatest: Bool

  @State private var drawProgress: CGFloat = 0
  @State private var dashOffset: CGFloat = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init(
    coordinates: [(lat: Double, lng: Double)],
    projection: SalishSeaProjection = .salishSea,
    color: Color,
    drawDuration: Double = 2.5,
    isLatest: Bool = false
  ) {
    self.coordinates = coordinates
    self.projection = projection
    self.color = color
    self.drawDuration = drawDuration
    self.isLatest = isLatest
  }

  public var body: some View {
    GeometryReader { geo in
      ZStack {
        Path { path in
          let pts = coordinates.map { coord in
            let rawPoint = projection.project(lat: coord.lat, lng: coord.lng)
            let p = (x: min(max(rawPoint.x, 0), 1), y: min(max(rawPoint.y, 0), 1))
            return CGPoint(x: CGFloat(p.x) * geo.size.width, y: CGFloat(p.y) * geo.size.height)
          }
          if let first = pts.first {
            path.move(to: first)
            for pt in pts.dropFirst() {
              path.addLine(to: pt)
            }
          }
        }
        .trim(from: 0, to: drawProgress)
        .stroke(
          color,
          style: StrokeStyle(
            lineWidth: 2.5,
            lineCap: .round,
            lineJoin: .round,
            dash: Self.dashPattern(
              drawComplete: drawProgress >= 1,
              reduceMotion: reduceMotion
            ),
            dashPhase: dashOffset
          )
        )

        if let lastCoord = coordinates.last, isLatest {
          let rawPoint = projection.project(lat: lastCoord.lat, lng: lastCoord.lng)
          let p = (x: min(max(rawPoint.x, 0), 1), y: min(max(rawPoint.y, 0), 1))
          PulsingEndpoint(color: color)
            .position(x: CGFloat(p.x) * geo.size.width, y: CGFloat(p.y) * geo.size.height)
            .opacity(drawProgress >= 1 ? 1 : 0)
        }
      }
    }
    .onAppear {
      updateAnimation(reduceMotion: reduceMotion)
    }
    .onChange(of: reduceMotion) { _, isEnabled in
      updateAnimation(reduceMotion: isEnabled)
    }
  }

  public static func dashPattern(drawComplete: Bool, reduceMotion: Bool) -> [CGFloat] {
    drawComplete && !reduceMotion ? [8, 6] : []
  }

  private func updateAnimation(reduceMotion: Bool) {
    if reduceMotion {
      var transaction = Transaction(animation: nil)
      transaction.disablesAnimations = true
      withTransaction(transaction) {
        drawProgress = 1
        dashOffset = 0
      }
    } else {
      drawProgress = 0
      dashOffset = 0
      withAnimation(.easeOut(duration: drawDuration)) {
        drawProgress = 1
      }
      withAnimation(
        .linear(duration: 1.4)
          .repeatForever(autoreverses: false)
          .delay(drawDuration)
      ) {
        dashOffset = -40
      }
    }
  }
}

private struct PulsingEndpoint: View {
  let color: Color
  @State private var scale: CGFloat = 1
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      Circle()
        .stroke(color.opacity(0.45), lineWidth: 2)
        .scaleEffect(scale)
        .opacity(2 - scale)
        .frame(width: 12, height: 12)
      Circle()
        .fill(color)
        .frame(width: 8, height: 8)
    }
    .onAppear {
      updateAnimation(reduceMotion: reduceMotion)
    }
    .onChange(of: reduceMotion) { _, isEnabled in
      updateAnimation(reduceMotion: isEnabled)
    }
  }

  private func updateAnimation(reduceMotion: Bool) {
    if reduceMotion {
      var transaction = Transaction(animation: nil)
      transaction.disablesAnimations = true
      withTransaction(transaction) { scale = 1 }
    } else {
      scale = 1
      withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
        scale = 2.4
      }
    }
  }
}
