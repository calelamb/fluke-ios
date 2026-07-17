import Foundation

public struct AuthenticatedUser: Codable, Hashable, Sendable, Identifiable {
  public let id: String
  public let email: String?
  public let displayName: String?
  public let role: String

  public init(id: String, email: String?, displayName: String?, role: String) {
    self.id = id
    self.email = email
    self.displayName = displayName
    self.role = role
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case id, email, displayName, role
  }

  public init(from decoder: any Decoder) throws {
    let dynamic = try decoder.container(keyedBy: AuthDynamicCodingKey.self)
    guard Set(dynamic.allKeys.map(\.stringValue)) == Set(CodingKeys.allCases.map(\.stringValue))
    else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "Unexpected user keys")
      )
    }
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    email = try container.decodeIfPresent(String.self, forKey: .email)
    displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
    role = try container.decode(String.self, forKey: .role)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(email, forKey: .email)
    try container.encode(displayName, forKey: .displayName)
    try container.encode(role, forKey: .role)
  }
}

public struct AppleCredential: Hashable, Sendable {
  public let authorizationCode: Data
  public let identityToken: Data
  public let nonce: String
  public let fullName: String?

  public init(
    authorizationCode: Data,
    identityToken: Data,
    nonce: String,
    fullName: String?
  ) {
    self.authorizationCode = authorizationCode
    self.identityToken = identityToken
    self.nonce = nonce
    self.fullName = fullName
  }

  public var isStructurallyValid: Bool {
    guard let authorizationCode = String(data: authorizationCode, encoding: .utf8),
      let identityToken = String(data: identityToken, encoding: .utf8)
    else { return false }
    return Self.isBoundedText(authorizationCode, maximum: 4_096)
      && Self.isBoundedText(identityToken, maximum: 16_384)
      && nonce.count >= 32 && nonce.count <= 256
      && nonce.unicodeScalars.allSatisfy {
        CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
      }
  }

  private static func isBoundedText(_ value: String, maximum: Int) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return !trimmed.isEmpty && trimmed.count <= maximum
      && trimmed.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
  }
}

public enum AuthServiceError: Error, Equatable, Sendable {
  case invalidAppleCredential
}

struct AppleSignInRequest: Encodable, Sendable {
  let authorizationCode: String
  let identityToken: String
  let nonce: String
  let fullName: String?
}

struct DeleteAccountRequest: Encodable, Sendable {
  let authorizationCode: String
  let identityToken: String
  let nonce: String
}

struct AppleSignInResponse: Decodable, Sendable {
  let csrfToken: String
  let user: AuthenticatedUser

  private enum CodingKeys: String, CodingKey, CaseIterable { case csrfToken, user }

  init(from decoder: any Decoder) throws {
    let dynamic = try decoder.container(keyedBy: AuthDynamicCodingKey.self)
    guard Set(dynamic.allKeys.map(\.stringValue)) == ["csrfToken", "user"] else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "Unexpected response keys")
      )
    }
    let container = try decoder.container(keyedBy: CodingKeys.self)
    guard Set(container.allKeys) == Set(CodingKeys.allCases) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "Unexpected response keys")
      )
    }
    csrfToken = try container.decode(String.self, forKey: .csrfToken)
    user = try container.decode(AuthenticatedUser.self, forKey: .user)
  }
}

private struct AuthDynamicCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int? = nil
  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { return nil }
}

struct CurrentObserverResponse: Decodable, Sendable {
  let id: String
  let email: String?
  let displayName: String?
  let role: String
  let userId: String

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case id, email, displayName, role, userId
  }

  init(from decoder: any Decoder) throws {
    let dynamic = try decoder.container(keyedBy: AuthDynamicCodingKey.self)
    guard Set(dynamic.allKeys.map(\.stringValue)) == Set(CodingKeys.allCases.map(\.stringValue))
    else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "Unexpected current-user keys")
      )
    }
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    email = try container.decodeIfPresent(String.self, forKey: .email)
    displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
    role = try container.decode(String.self, forKey: .role)
    userId = try container.decode(String.self, forKey: .userId)
  }
}
