import SwiftUI

/// Hand-illustrated Salish Sea coastline drawn as a SwiftUI Shape.
/// Reads the baked JSON resource at first construction; subsequent
/// reads hit a static cache.
public struct SalishSeaShape: Shape {

    public init() {}

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        for polygon in Self.polygons {
            guard polygon.points.count >= 2 else { continue }
            let first = projected(polygon.points[0], in: rect)
            path.move(to: first)
            for point in polygon.points.dropFirst() {
                path.addLine(to: projected(point, in: rect))
            }
        }
        return path
    }

    private func projected(_ p: CoastlinePoint, in rect: CGRect) -> CGPoint {
        // Equirectangular: x = (lng - west) / (east - west)
        //                  y = (north - lat) / (north - south)
        // Salish Sea bbox baked into the JSON.
        let west = -124.7, east = -122.0, north = 49.5, south = 47.0
        let nx = (p.lng - west) / (east - west)
        let ny = (north - p.lat) / (north - south)
        return CGPoint(
            x: rect.minX + CGFloat(nx) * rect.width,
            y: rect.minY + CGFloat(ny) * rect.height
        )
    }

    // MARK: - Static cache

    private struct CoastlinePoint: Decodable {
        let lat: Double
        let lng: Double

        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            self.lat = try c.decode(Double.self)
            self.lng = try c.decode(Double.self)
        }
    }

    private struct Polygon: Decodable {
        let name: String
        let tier: String
        let points: [CoastlinePoint]
    }

    private struct Manifest: Decodable {
        let bbox: [Double]
        let polygons: [Polygon]
    }

    private static let polygons: [Polygon] = {
        guard let url = Bundle.module.url(
            forResource: "salish-sea-coastline",
            withExtension: "json"
        ),
        let data = try? Data(contentsOf: url),
        let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        else {
            assertionFailure("salish-sea-coastline.json missing or unparseable")
            return []
        }
        return manifest.polygons
    }()
}

// MARK: - Public named-features API (used by BasemapView)

public struct SalishSeaFeature: Decodable, Identifiable, Sendable {
    public let name: String
    public let lat: Double
    public let lng: Double
    public let kind: String
    public var id: String { name }
}

public extension SalishSeaShape {
    /// Hand-curated named bays / sounds / inlets / land, loaded from
    /// the bundled JSON resource.
    static let namedFeatures: [SalishSeaFeature] = {
        struct Manifest: Decodable { let features: [SalishSeaFeature] }
        guard let url = Bundle.module.url(
            forResource: "salish-sea-features",
            withExtension: "json"
        ),
        let data = try? Data(contentsOf: url),
        let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        else { return [] }
        return manifest.features
    }()
}
