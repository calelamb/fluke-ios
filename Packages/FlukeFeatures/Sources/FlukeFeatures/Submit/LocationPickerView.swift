import FlukeUI
import MapKit
import SwiftUI

public enum LocationPickerPresentation: Sendable {
  case interactiveMap
  case deterministicPreview
}

private struct LocationPickerPresentationKey: EnvironmentKey {
  static let defaultValue = LocationPickerPresentation.interactiveMap
}

extension EnvironmentValues {
  public var locationPickerPresentation: LocationPickerPresentation {
    get { self[LocationPickerPresentationKey.self] }
    set { self[LocationPickerPresentationKey.self] = newValue }
  }
}

public struct SubmissionCoordinate: Equatable, Sendable {
  public let latitude: Double
  public let longitude: Double

  public init(latitude: Double, longitude: Double) {
    self.latitude = Self.coarse(min(max(latitude, -90), 90))
    self.longitude = Self.coarse(Self.wrapped(longitude))
  }

  private static func coarse(_ value: Double) -> Double {
    (value * 100).rounded() / 100
  }

  private static func wrapped(_ longitude: Double) -> Double {
    let value = longitude.truncatingRemainder(dividingBy: 360)
    if value > 180 { return value - 360 }
    if value < -180 { return value + 360 }
    return value
  }
}

public struct LocationPickerView: View {
  @Environment(\.locationPickerPresentation) private var presentation
  @Binding var latitude: Double
  @Binding var longitude: Double
  @State private var position = MapCameraPosition.region(
    MKCoordinateRegion(
      center: CLLocationCoordinate2D(latitude: 48.52, longitude: -123.15),
      span: MKCoordinateSpan(latitudeDelta: 3, longitudeDelta: 3)
    ))

  public init(latitude: Binding<Double>, longitude: Binding<Double>) {
    _latitude = latitude
    _longitude = longitude
  }

  public var body: some View {
    Group {
      switch presentation {
      case .interactiveMap:
        interactiveMap
      case .deterministicPreview:
        SalishSeaLocationPreview(latitude: latitude, longitude: longitude)
      }
    }
    .frame(minHeight: 180)
    .accessibilityLabel("Sighting coordinate picker centered on the Salish Sea")
  }

  private var interactiveMap: some View {
    Map(position: $position) {
      Marker(
        "Observation", coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
      )
    }
    .onMapCameraChange(frequency: .onEnd) { context in
      let selected = SubmissionCoordinate(
        latitude: context.region.center.latitude,
        longitude: context.region.center.longitude
      )
      latitude = selected.latitude
      longitude = selected.longitude
    }
    .overlay {
      Image(systemName: "plus.circle.fill")
        .font(.title)
        .foregroundStyle(Color.accentColor)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
  }
}

private struct SalishSeaLocationPreview: View {
  let latitude: Double
  let longitude: Double

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [Color.mist.opacity(0.72), Color.tide.opacity(0.34)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      stylizedCoastline
      VStack(alignment: .leading, spacing: 4) {
        Text("SALISH SEA")
          .font(.flukeLabel)
          .foregroundStyle(Color.abyss.opacity(0.72))
        Spacer()
        Text("Coarse coordinate preview")
          .font(.caption.weight(.semibold))
          .foregroundStyle(Color.deep)
        Text(String(format: "%.2f°, %.2f°", latitude, longitude))
          .font(.caption.monospacedDigit())
          .foregroundStyle(Color.abyss)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      .padding(14)

      Image(systemName: "plus.circle.fill")
        .font(.title)
        .foregroundStyle(Color.tide)
        .background(Color.bone, in: Circle())
        .accessibilityHidden(true)
    }
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(Color.tide.opacity(0.35), lineWidth: 1)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityIdentifier("location.preview")
    .accessibilityLabel(
      "Coarse coordinate preview, latitude \(latitude), longitude \(longitude)"
    )
  }

  private var stylizedCoastline: some View {
    GeometryReader { proxy in
      Path { path in
        let width = proxy.size.width
        let height = proxy.size.height
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: width * 0.38, y: 0))
        path.addCurve(
          to: CGPoint(x: width * 0.28, y: height),
          control1: CGPoint(x: width * 0.48, y: height * 0.25),
          control2: CGPoint(x: width * 0.16, y: height * 0.62)
        )
        path.addLine(to: CGPoint(x: 0, y: height))
        path.closeSubpath()
      }
      .fill(Color.bone.opacity(0.82))

      Capsule()
        .fill(Color.bone.opacity(0.74))
        .frame(width: proxy.size.width * 0.16, height: proxy.size.height * 0.72)
        .rotationEffect(.degrees(18))
        .position(x: proxy.size.width * 0.72, y: proxy.size.height * 0.42)
    }
    .accessibilityHidden(true)
  }
}
