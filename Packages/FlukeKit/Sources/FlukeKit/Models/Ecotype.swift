import Foundation

public enum Ecotype: String, Codable, Hashable, Sendable, CaseIterable {
  case resident = "RESIDENT"
  case biggs = "BIGGS"
  case offshore = "OFFSHORE"
  case unknown = "UNKNOWN"

  public init(from decoder: Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    self = Ecotype(rawValue: raw) ?? .unknown
  }
}
