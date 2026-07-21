import Foundation

enum EmailAddressValidator {
  private static let localSpecials = CharacterSet(
    charactersIn: "!#$%&'*+-/=?^_`{|}~."
  )

  static func isValid(_ rawValue: String) -> Bool {
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard value == rawValue,
      value.count <= 254,
      value.unicodeScalars.allSatisfy(\.isASCII)
    else { return false }

    let parts = value.split(separator: "@", omittingEmptySubsequences: false)
    guard parts.count == 2 else { return false }
    let local = String(parts[0])
    let domain = String(parts[1])
    return isValidLocalPart(local) && isValidDomain(domain)
  }

  private static func isValidLocalPart(_ value: String) -> Bool {
    guard (1...64).contains(value.count),
      value.first != ".",
      value.last != ".",
      !value.contains("..")
    else { return false }
    return value.unicodeScalars.allSatisfy {
      CharacterSet.alphanumerics.contains($0) || localSpecials.contains($0)
    }
  }

  private static func isValidDomain(_ value: String) -> Bool {
    let labels = value.split(separator: ".", omittingEmptySubsequences: false)
    guard value.count <= 253, labels.count >= 2 else { return false }
    return labels.allSatisfy { label in
      guard (1...63).contains(label.count),
        label.first != "-",
        label.last != "-"
      else { return false }
      return label.unicodeScalars.allSatisfy {
        CharacterSet.alphanumerics.contains($0) || $0 == "-"
      }
    }
  }
}
