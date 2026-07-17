import Foundation

public enum PublicBrowseValidator {
    public static func whales(_ values: [Whale]) throws {
        try values.forEach(validateWhale)
    }

    public static func whaleProfile(_ value: WhaleProfile) throws {
        try validateWhale(value.whale)
        if let mother = value.mother { try stableID(mother.catalogId) }
        try value.offspring.forEach { try stableID($0.catalogId) }
        try value.recentSightings.forEach { sighting in
            try stableID(sighting.id)
            try coordinates(latitude: sighting.latitude, longitude: sighting.longitude)
            try validDate(sighting.observedAt)
        }
    }

    public static func sightings(_ values: [Sighting]) throws {
        try values.forEach { sighting in
            try stableID(sighting.id)
            try coordinates(latitude: sighting.latitude, longitude: sighting.longitude)
            try validDate(sighting.observedAt)
            try sighting.photoUrls.forEach(httpURL)
            try sighting.photos.forEach { photo in
                try stableID(photo.id)
                try httpURL(photo.url)
                try httpURL(photo.thumbnailUrl)
            }
            try sighting.identifiedWhales.forEach { try stableID($0.catalogId) }
        }
    }

    public static func externalSightings(_ values: [ExternalSighting]) throws {
        try values.forEach { sighting in
            try stableID(sighting.id)
            try stableID(sighting.externalId)
            try coordinates(latitude: sighting.latitude, longitude: sighting.longitude)
            try validDate(sighting.observedAt)
            if let sourceURL = sighting.sourceURL { try httpURL(sourceURL) }
        }
    }

    public static func historicalSightings(_ values: [HistoricalSighting]) throws {
        try values.forEach { sighting in
            try stableID(sighting.id)
            try coordinates(latitude: sighting.latitude, longitude: sighting.longitude)
            try validDate(sighting.observedAt)
            try sighting.whaleIds.forEach(stableID)
        }
    }

    public static func track(_ values: [MovementTrackPoint]) throws {
        try values.forEach { point in
            try stableID(point.id)
            try coordinates(latitude: point.latitude, longitude: point.longitude)
            try validDate(point.observedAt)
        }
    }

    public static func prediction(_ value: Prediction) throws {
        try probability(value.confidence)
        try validDate(value.computedAt)
        try value.cells.forEach { cell in
            try coordinates(latitude: cell.lat, longitude: cell.lng)
            try probability(cell.probability)
        }
    }

    private static func validateWhale(_ whale: Whale) throws {
        try stableID(whale.id)
        try stableID(whale.catalogId)
        if let heroImageURL = whale.heroImageUrl { try httpURL(heroImageURL) }
        try whale.sourceCitations.forEach { try httpURL($0.url) }
    }

    private static func stableID(_ value: String) throws {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= 200 else {
            throw APIError.malformedResponse
        }
    }

    private static func httpURL(_ value: String) throws {
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host != nil else {
            throw APIError.malformedResponse
        }
    }

    private static func coordinates(latitude: Double, longitude: Double) throws {
        guard latitude.isFinite, (-90...90).contains(latitude),
              longitude.isFinite, (-180...180).contains(longitude) else {
            throw APIError.malformedResponse
        }
    }

    private static func probability(_ value: Double) throws {
        guard value.isFinite, (0...1).contains(value) else {
            throw APIError.malformedResponse
        }
    }

    private static func validDate(_ value: Date) throws {
        guard value.timeIntervalSinceReferenceDate.isFinite else {
            throw APIError.malformedResponse
        }
    }
}
