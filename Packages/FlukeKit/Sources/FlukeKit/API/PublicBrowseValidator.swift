import Foundation

public enum PublicBrowseValidator {
    private static let maximumNestedCount = 100
    private static let maximumTextCount = 10_000
    private static let maximumNameCount = 500

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
            try optionalText(mother.name, maximum: maximumNameCount)
        }
        try value.offspring.forEach {
            try stableID($0.catalogId)
            try optionalText($0.name, maximum: maximumNameCount)
        }
        try value.recentSightings.forEach { sighting in
            try stableID(sighting.id)
            try coordinates(latitude: sighting.latitude, longitude: sighting.longitude)
            try validDate(sighting.observedAt)
            try optionalText(sighting.locationName, maximum: maximumNameCount)
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
            guard sighting.status == .approved else { throw APIError.malformedResponse }
            try optionalText(sighting.locationName, maximum: maximumNameCount)
            try optionalText(sighting.behaviorNotes, maximum: maximumTextCount)
            try groupSize(sighting.groupSize)
            try sighting.photoUrls.forEach(httpURL)
            try sighting.photos.forEach { photo in
                try stableID(photo.id)
                try httpURL(photo.url)
                try httpURL(photo.thumbnailUrl)
                guard photo.orderIndex >= 0 else { throw APIError.malformedResponse }
            }
            try sighting.identifiedWhales.forEach {
                try stableID($0.catalogId)
                try optionalText($0.name, maximum: maximumNameCount)
            }
        }
    }

    public static func externalSightings(_ values: [ExternalSighting]) throws {
        try values.forEach { sighting in
            try stableID(sighting.id)
            try stableID(sighting.externalId)
            try coordinates(latitude: sighting.latitude, longitude: sighting.longitude)
            try validDate(sighting.observedAt)
            try requiredText(sighting.source, maximum: maximumNameCount)
            try requiredText(sighting.externalId, maximum: maximumNameCount)
            try requiredText(sighting.species, maximum: maximumNameCount)
            try requiredText(sighting.attribution, maximum: maximumTextCount)
            try optionalText(sighting.notes, maximum: maximumTextCount)
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
            try optionalText(sighting.locationName, maximum: maximumNameCount)
            try sighting.whaleIds.forEach(stableID)
        }
    }

    public static func track(_ values: [MovementTrackPoint]) throws {
        guard values.count <= 10_000 else { throw APIError.malformedResponse }
        try values.forEach { point in
            try stableID(point.id)
            try coordinates(latitude: point.latitude, longitude: point.longitude)
            try validDate(point.observedAt)
            try optionalText(point.locationName, maximum: maximumNameCount)
            try optionalText(point.behaviorNotes, maximum: maximumTextCount)
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
        guard value.cells.count <= 10_000 else { throw APIError.malformedResponse }
        try probability(value.confidence)
        try validDate(value.computedAt)
        try requiredText(value.modelVersion, maximum: maximumNameCount)
        try value.cells.forEach { cell in
            try coordinates(latitude: cell.lat, longitude: cell.lng)
            try probability(cell.probability)
        }
    }

    private static func validateWhale(_ whale: Whale) throws {
        try stableID(whale.id)
        try stableID(whale.catalogId)
        try optionalText(whale.name, maximum: maximumNameCount)
        try optionalText(whale.pod, maximum: maximumNameCount)
        try optionalText(whale.biography, maximum: maximumTextCount)
        try optionalText(whale.distinguishingMarks, maximum: maximumTextCount)
        try boundedArray(whale.notableEvents)
        try boundedArray(whale.sourceCitations)
        if let birthYear = whale.birthYear { try year(birthYear) }
        if let deathYear = whale.deathYear {
            try year(deathYear)
            if let birthYear = whale.birthYear, deathYear < birthYear {
                throw APIError.malformedResponse
            }
            if whale.status == .alive { throw APIError.malformedResponse }
        }
        if let heroImageURL = whale.heroImageUrl { try httpURL(heroImageURL) }
        try whale.notableEvents.forEach { event in
            try year(event.year)
            try requiredText(event.summary, maximum: 2_000)
            try optionalText(event.date, maximum: maximumNameCount)
            try optionalText(event.source, maximum: maximumTextCount)
        }
        try whale.sourceCitations.forEach {
            try requiredText($0.label, maximum: maximumNameCount)
            try httpURL($0.url)
        }
    }

    private static func stableID(_ value: String) throws {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              normalized.count <= 200,
              normalized.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw APIError.malformedResponse
        }
    }

    private static func boundedArray<Value>(_ values: [Value], maximum: Int = maximumNestedCount) throws {
        guard values.count <= maximum else { throw APIError.malformedResponse }
    }

    private static func optionalText(_ value: String?, maximum: Int) throws {
        guard let value else { return }
        try requiredText(value, maximum: maximum)
    }

    private static func requiredText(_ value: String, maximum: Int) throws {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              normalized.count <= maximum,
              normalized.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw APIError.malformedResponse
        }
    }

    private static func groupSize(_ value: Int?) throws {
        guard let value else { return }
        guard (1...1_000).contains(value) else { throw APIError.malformedResponse }
    }

    private static func year(_ value: Int) throws {
        let maximum = Calendar(identifier: .gregorian).component(.year, from: Date()) + 1
        guard (1800...maximum).contains(value) else { throw APIError.malformedResponse }
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
