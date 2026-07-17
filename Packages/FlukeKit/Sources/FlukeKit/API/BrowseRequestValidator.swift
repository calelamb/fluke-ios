import Foundation

public enum BrowseRequestValidator {
    public static let maximumWindow: TimeInterval = 366 * 86_400

    public static func dateWindow(from: Date, to: Date) throws {
        let fromValue = from.timeIntervalSinceReferenceDate
        let toValue = to.timeIntervalSinceReferenceDate
        guard fromValue.isFinite, toValue.isFinite,
              from <= to,
              to.timeIntervalSince(from) <= maximumWindow else {
            throw APIError.invalidRequest
        }
    }

    public static func identifier(_ value: String, pathSegment: Bool = false) throws {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= 200,
              normalized.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw APIError.invalidRequest
        }
        if pathSegment,
           normalized.contains("/") || normalized.contains("\\")
            || normalized.contains("?") || normalized.contains("#")
            || normalized.contains("..") {
            throw APIError.invalidRequest
        }
    }

    public static func text(_ value: String, maximumCount: Int) throws {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= maximumCount,
              normalized.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw APIError.invalidRequest
        }
    }
}
