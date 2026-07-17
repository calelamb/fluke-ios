import FlukeKit
import FlukeUI
import SwiftUI

public struct SightingsMapView: View {
    let items: [SightingsViewModel.DisplayItem]
    let select: (SightingsViewModel.DisplayItem) -> Void

    public init(
        items: [SightingsViewModel.DisplayItem],
        select: @escaping (SightingsViewModel.DisplayItem) -> Void
    ) {
        self.items = items
        self.select = select
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                BasemapView()
                ForEach(items) { item in
                    let point = SalishSeaProjection.salishSea.project(
                        lat: item.latitude,
                        lng: item.longitude
                    )
                    Button {
                        select(item)
                    } label: {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.ember)
                            .frame(width: 44, height: 44)
                            .background(Color.bone.opacity(0.84), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .position(
                        x: CGFloat(point.x) * geometry.size.width,
                        y: CGFloat(point.y) * geometry.size.height
                    )
                    .accessibilityLabel(item.accessibilityLabel)
                    .accessibilityHint("Opens sighting details")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recent sightings map")
    }
}
