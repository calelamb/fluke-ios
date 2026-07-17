import MapKit
import SwiftUI

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
    .frame(minHeight: 180)
    .accessibilityLabel("Sighting coordinate picker centered on the Salish Sea")
  }
}
