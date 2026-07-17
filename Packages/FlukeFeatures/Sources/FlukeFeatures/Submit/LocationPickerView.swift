import MapKit
import SwiftUI

public struct SubmissionCoordinate: Equatable, Sendable {
  public let latitude: Double
  public let longitude: Double

  public init(latitude: Double, longitude: Double) {
    self.latitude = min(max(latitude, -90), 90)
    self.longitude = Self.wrapped(longitude)
  }

  private static func wrapped(_ longitude: Double) -> Double {
    let value = longitude.truncatingRemainder(dividingBy: 360)
    if value > 180 { return value - 360 }
    if value < -180 { return value + 360 }
    return value
  }
}

public struct LocationPickerView: View {
  @Binding var latitude: Double
  @Binding var longitude: Double
  @State private var position = MapCameraPosition.region(MKCoordinateRegion(
    center: CLLocationCoordinate2D(latitude: 48.52, longitude: -123.15),
    span: MKCoordinateSpan(latitudeDelta: 3, longitudeDelta: 3)
  ))

  public init(latitude: Binding<Double>, longitude: Binding<Double>) {
    _latitude = latitude
    _longitude = longitude
  }

  public var body: some View {
    Map(position: $position) {
      Marker("Observation", coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
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
    .frame(minHeight: 180)
    .accessibilityLabel("Sighting coordinate picker centered on the Salish Sea")
  }
}
