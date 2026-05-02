import Foundation

public enum Pod: String, Codable, CaseIterable, Sendable {
    case j = "J"
    case k = "K"
    case l = "L"
    case biggs = "BIGGS"

    public var displayName: String {
        switch self {
        case .j: return "J pod"
        case .k: return "K pod"
        case .l: return "L pod"
        case .biggs: return "Bigg's"
        }
    }
}
