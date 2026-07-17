import Foundation

public enum PublicBrowseValidator {
    private static let maximumNestedCount = 1_000
    private static let maximumTextCount = 20_000
    private static let maximumURLCount = 2_048
    private static let javascriptWhitespace = CharacterSet.whitespacesAndNewlines.union(
        CharacterSet(charactersIn: "\u{FEFF}")
    )

    public static func whales(_ values: [Whale]) throws {
        try values.forEach(validateWhale)
    }

    public static func whaleProfile(_ value: WhaleProfile, requestedID: String? = nil) throws {
        try validateWhale(value.whale)
        if let requestedID,
           requestedID != value.id,
           requestedID != value.catalogId {
            throw APIError.malformedResponse
        }
        try boundedArray(value.offspring)
        try boundedArray(value.recentSightings, maximum: 1_000)
        if let mother = value.mother {
            try stableID(mother.catalogId)
            try optionalText(mother.name)
        }
        try value.offspring.forEach {
            try stableID($0.catalogId)
            try optionalText($0.name)
        }
        try value.recentSightings.forEach { sighting in
            try stableID(sighting.id)
            try coordinates(latitude: sighting.latitude, longitude: sighting.longitude)
            try validDate(sighting.observedAt)
            try optionalText(sighting.locationName)
        }
    }

    public static func sightings(_ values: [Sighting]) throws {
        try values.forEach { sighting in
            try boundedArray(sighting.photoUrls)
            try boundedArray(sighting.photos)
            try boundedArray(sighting.identifiedWhales)
            try stableID(sighting.id)
            try coordinates(latitude: sighting.latitude, longitude: sighting.longitude)
            try validDate(sighting.observedAt)
            try optionalText(sighting.locationName)
            try optionalText(sighting.behaviorNotes)
            try groupSize(sighting.groupSize)
            try sighting.photoUrls.forEach(httpURL)
            try sighting.photos.forEach { photo in
                try stableID(photo.id)
                try httpURL(photo.url)
                try httpURL(photo.thumbnailUrl)
            }
            try sighting.identifiedWhales.forEach {
                try stableID($0.catalogId)
                try optionalText($0.name)
            }
        }
    }

    public static func externalSightings(_ values: [ExternalSighting]) throws {
        try values.forEach { sighting in
            try stableID(sighting.id)
            try stableID(sighting.externalId)
            try coordinates(latitude: sighting.latitude, longitude: sighting.longitude)
            try validDate(sighting.observedAt)
            try boundedText(sighting.source)
            try boundedText(sighting.species)
            try boundedText(sighting.attribution)
            try optionalText(sighting.notes)
            try groupSize(sighting.groupSize)
            if let sourceURL = sighting.sourceURL { try httpURL(sourceURL) }
        }
    }

    public static func historicalSightings(_ values: [HistoricalSighting]) throws {
        try values.forEach { sighting in
            try boundedArray(sighting.whaleIds)
            try stableID(sighting.id)
            try coordinates(latitude: sighting.latitude, longitude: sighting.longitude)
            try validDate(sighting.observedAt)
            try optionalText(sighting.locationName)
            try sighting.whaleIds.forEach(stableID)
        }
    }

    public static func track(_ values: [MovementTrackPoint]) throws {
        try boundedArray(values)
        try values.forEach { point in
            try stableID(point.id)
            try coordinates(latitude: point.latitude, longitude: point.longitude)
            try validDate(point.observedAt)
            try optionalText(point.locationName)
            try optionalText(point.behaviorNotes)
        }
    }

    public static func whaleTrack(_ value: WhaleTrack, requestedID: String) throws {
        try stableID(value.whaleId)
        try stableID(value.catalogId)
        guard requestedID == value.whaleId || requestedID == value.catalogId else {
            throw APIError.malformedResponse
        }
        try track(value.points)
    }

    public static func prediction(_ value: Prediction) throws {
        try boundedArray(value.cells)
        try probability(value.confidence)
        try validDate(value.computedAt)
        try boundedText(value.modelVersion)
        try value.cells.forEach { cell in
            try coordinates(latitude: cell.lat, longitude: cell.lng)
            try probability(cell.probability)
        }
    }

    private static func validateWhale(_ whale: Whale) throws {
        try stableID(whale.id)
        try stableID(whale.catalogId)
        try optionalText(whale.name)
        try optionalText(whale.pod)
        try optionalText(whale.biography)
        try optionalText(whale.distinguishingMarks)
        try boundedArray(whale.notableEvents)
        try boundedArray(whale.sourceCitations)
        if let birthYear = whale.birthYear { try year(birthYear) }
        if let deathYear = whale.deathYear { try year(deathYear) }
        if let heroImageURL = whale.heroImageUrl { try httpURL(heroImageURL) }
        try whale.notableEvents.forEach { event in
            try year(event.year)
            try boundedText(event.summary)
            try optionalText(event.date)
            try optionalText(event.source)
        }
        try whale.sourceCitations.forEach {
            try boundedText($0.label)
            try httpURL($0.url)
        }
    }

    private static func stableID(_ value: String) throws {
        guard value.utf16.count <= 200,
              value.unicodeScalars.contains(where: {
                  !javascriptWhitespace.contains($0)
              }) else {
            throw APIError.malformedResponse
        }
    }

    private static func boundedArray<Value>(_ values: [Value], maximum: Int = maximumNestedCount) throws {
        guard values.count <= maximum else { throw APIError.malformedResponse }
    }

    private static func optionalText(_ value: String?) throws {
        guard let value else { return }
        try boundedText(value)
    }

    private static func boundedText(_ value: String) throws {
        guard value.utf16.count <= maximumTextCount else { throw APIError.malformedResponse }
    }

    private static func groupSize(_ value: Int?) throws {
        guard let value else { return }
        guard (1...200).contains(value) else { throw APIError.malformedResponse }
    }

    private static func year(_ value: Int) throws {
        guard (1_000...9_999).contains(value) else { throw APIError.malformedResponse }
    }

    private static func httpURL(_ value: String) throws {
        guard value.utf16.count <= maximumURLCount,
              let components = URLComponents(string: value),
              let scheme = components.scheme,
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
