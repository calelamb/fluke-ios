import Foundation

public struct Prediction: Codable, Sendable {
    public let cells: [PredictionCell]
    public let confidence: Double
    public let modelVersion: String
    public let computedAt: Date

    public init(cells: [PredictionCell], confidence: Double, modelVersion: String, computedAt: Date) {
        self.cells = cells
        self.confidence = confidence
        self.modelVersion = modelVersion
        self.computedAt = computedAt
    }
}

public enum PredictionHorizon: String, CaseIterable, Sendable {
    case h24 = "24h"
    case d7 = "7d"
    case d30 = "30d"

    public var displayName: String {
        switch self {
        case .h24: return "24h"
        case .d7: return "7 days"
        case .d30: return "30 days"
        }
    }
}
