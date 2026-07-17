import Foundation

public struct LearnSection: Hashable, Sendable {
    public let heading: String
    public let body: String

    public init(heading: String, body: String) {
        self.heading = heading
        self.body = body
    }
}

public struct LearnSource: Hashable, Sendable {
    public let label: String
    public let url: URL

    public init(label: String, url: URL) {
        self.label = label
        self.url = url
    }
}

public struct LearnArticle: Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let summary: String
    public let sections: [LearnSection]
    public let sources: [LearnSource]

    public init(
        id: String,
        title: String,
        summary: String,
        sections: [LearnSection],
        sources: [LearnSource]
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.sections = sections
        self.sources = sources
    }
}

public enum LearnContent {
    public static let articles: [LearnArticle] = [
        LearnArticle(
            id: "ecotypes",
            title: "Four ways of living",
            summary: "Resident, Bigg's, offshore, and unknown describe ecology—not rank or personality.",
            sections: [
                LearnSection(
                    heading: "Resident",
                    body: "Southern Resident killer whales travel in enduring family groups and specialize on fish. J, K, and L pods are the catalog groups most often discussed in the Salish Sea."
                ),
                LearnSection(
                    heading: "Bigg's",
                    body: "Bigg's killer whales eat marine mammals and often travel in smaller groups. Their quieter hunting behavior and changing family associations differ from resident patterns."
                ),
                LearnSection(
                    heading: "Offshore and unknown",
                    body: "Offshore killer whales range widely and are encountered less often near shore. Unknown is an honest label when the available evidence does not support a more specific classification."
                ),
            ],
            sources: [source("NOAA Fisheries: Killer Whale", "https://www.fisheries.noaa.gov/species/killer-whale")]
        ),
        LearnArticle(
            id: "catalog-evidence",
            title: "How a whale enters the catalog",
            summary: "Catalog identity comes from repeated, reviewable evidence across encounters.",
            sections: [
                LearnSection(
                    heading: "Natural marks",
                    body: "Researchers compare the dorsal fin, saddle patch, scars, and stable notches. Age, viewing angle, light, and image quality can change how those features appear."
                ),
                LearnSection(
                    heading: "Identity remains evidence-based",
                    body: "A catalog number is useful because observations can be connected over time. Names make stories easier to remember, but the catalog identity is the durable reference."
                ),
            ],
            sources: [source("Center for Whale Research", "https://www.whaleresearch.com/")]
        ),
        LearnArticle(
            id: "reading-sightings",
            title: "Reading a sighting",
            summary: "Time, place, source, group size, and certainty each describe a different part of an observation.",
            sections: [
                LearnSection(
                    heading: "What the map can say",
                    body: "A marker records where an observation was reported. It does not imply a whale stayed there, followed a straight route, or will return on a schedule."
                ),
                LearnSection(
                    heading: "Why sources matter",
                    body: "Fluke records and trusted external records share one timeline while preserving their attribution. Details may differ because organizations collect and review observations in different ways."
                ),
            ],
            sources: [source("Fluke public data", "https://fluke-api.onrender.com/api/v1/health")]
        ),
        LearnArticle(
            id: "responsible-viewing",
            title: "Watch without changing the scene",
            summary: "Good wildlife viewing leaves space, limits noise, and follows the current local rules.",
            sections: [
                LearnSection(
                    heading: "Distance is protection",
                    body: "Regulations vary by place, species, and vessel. Check the current official guidance before heading out, slow down around wildlife, and never position a vessel in an animal's path."
                ),
                LearnSection(
                    heading: "Shore is part of the habitat",
                    body: "Use established viewpoints, keep pets controlled, pack out waste, and avoid crowding other observers. A longer lens is safer than moving closer."
                ),
            ],
            sources: [source("NOAA whale viewing guidance", "https://www.fisheries.noaa.gov/topic/marine-life-viewing-guidelines")]
        ),
        LearnArticle(
            id: "freshness-and-sources",
            title: "What saved data means",
            summary: "Fluke keeps the last validated public response so useful context can survive a weak connection.",
            sections: [
                LearnSection(
                    heading: "Fresh, stale, and offline",
                    body: "Fresh data came from the service during the current refresh. Stale data is the last validated copy shown alongside a safe refresh warning. Offline data is a validated saved copy shown when the network is unavailable."
                ),
                LearnSection(
                    heading: "No invented certainty",
                    body: "Empty means the public service returned no records for that request. An error without a saved copy remains an error. Fluke does not turn failed requests into an empty map."
                ),
            ],
            sources: [source("Fluke service status", "https://fluke-api.onrender.com/api/v1/health")]
        ),
    ]

    private static func source(_ label: String, _ value: String) -> LearnSource {
        guard let url = URL(string: value), url.scheme == "https", url.host != nil else {
            preconditionFailure("Invalid bundled Learn source URL")
        }
        return LearnSource(label: label, url: url)
    }
}
