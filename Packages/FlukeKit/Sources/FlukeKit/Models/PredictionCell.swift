import Foundation

public struct PredictionCell: Codable, Hashable, Sendable {
    public let lat: Double
    public let lng: Double
    public let probability: Double

    public init(lat: Double, lng: Double, probability: Double) {
        self.lat = lat
        self.lng = lng
        self.probability = probability
    }
}
