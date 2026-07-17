import Foundation

public enum Endpoint {
    public static let whales = "/api/v1/whales"
    public static let sightings = "/api/v1/sightings"
    public static let externalSightings = "/api/v1/external-sightings"

    public static func whale(id: String) throws -> String {
        try BrowseRequestValidator.identifier(id, pathSegment: true)
        return "/api/v1/whales/\(id)"
    }

    public static func whaleTrack(id: String) throws -> String {
        try BrowseRequestValidator.identifier(id, pathSegment: true)
        return "/api/v1/whales/\(id)/track"
    }

    public static let historicalSightings = "/api/v1/sightings/historical"
    public static let predict = "/api/v1/predict"
}
