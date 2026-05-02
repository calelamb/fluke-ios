import Foundation

/// Equirectangular projection mapping (lat, lng) into a normalized 0…1 box.
/// At the Salish Sea scale (~3° wide), the distortion is tolerable —
/// no Mercator needed.
public struct SalishSeaProjection: Sendable {

    public let south: Double
    public let west: Double
    public let north: Double
    public let east: Double

    public init(south: Double, west: Double, north: Double, east: Double) {
        self.south = south
        self.west = west
        self.north = north
        self.east = east
    }

    /// Default projection covering the Salish Sea bbox.
    public static let salishSea = SalishSeaProjection(
        south: 47.0,
        west: -124.7,
        north: 49.5,
        east: -122.0
    )

    /// Project (lat, lng) → (x, y) where x ∈ [0, 1] west→east and
    /// y ∈ [0, 1] north→south (image-coordinate convention).
    public func project(lat: Double, lng: Double) -> (x: Double, y: Double) {
        let x = (lng - west) / (east - west)
        let y = (north - lat) / (north - south)
        return (x, y)
    }

    /// Inverse of project.
    public func unproject(x: Double, y: Double) -> (lat: Double, lng: Double) {
        let lng = west + x * (east - west)
        let lat = north - y * (north - south)
        return (lat, lng)
    }
}
