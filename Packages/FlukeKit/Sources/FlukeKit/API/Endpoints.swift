import Foundation

public enum Endpoint {
    public static let whales = "/api/v1/whales"
    public static let sightings = "/api/v1/sightings"
    public static let externalSightings = "/api/v1/external-sightings"

    public static func whale(id: String) -> String { "/api/v1/whales/\(id)" }
    public static func whaleTrack(id: String) -> String { "/api/v1/whales/\(id)/track" }

    public static let identify = "/api/v1/identify"
    public static let mySightings = "/api/v1/sightings/me"

    public static let authMe = "/api/v1/auth/me"
    public static let authLogout = "/api/v1/auth/logout"
    public static let authApple = "/api/v1/auth/apple"

    public static let historicalSightings = "/api/v1/sightings/historical"
    public static let predict = "/api/v1/predict"
}
