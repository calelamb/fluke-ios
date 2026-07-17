import Foundation

public enum NotableEventType: String, Codable, CaseIterable, Sendable {
    case birth
    case death
    case loss
    case capture
    case release
    case podSwitch = "pod-switch"
    case firstDocumented = "first-documented"
    case milestone
}

public struct NotableEvent: Codable, Hashable, Sendable {
    public let year: Int
    public let date: String?
    public let type: NotableEventType
    public let summary: String
    public let source: String?

    public init(year: Int, date: String?, type: NotableEventType, summary: String, source: String?) {
        self.year = year
        self.date = date
        self.type = type
        self.summary = summary
        self.source = source
    }
}

public struct SourceCitation: Codable, Hashable, Sendable {
    public let label: String
    public let url: String

    public init(label: String, url: String) {
        self.label = label
        self.url = url
    }
}
