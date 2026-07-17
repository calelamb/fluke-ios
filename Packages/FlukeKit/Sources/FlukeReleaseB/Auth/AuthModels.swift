import Foundation

public struct AuthenticatedUser: Codable, Hashable, Sendable, Identifiable {
  public let id: String
  public let email: String
  public let displayName: String?
  public let role: String

  public init(id: String, email: String, displayName: String?, role: String) {
    self.id = id
    self.email = email
    self.displayName = displayName
    self.role = role
  }
}

public struct AppleCredential: Hashable, Sendable {
  public let identityToken: Data
  public let fullName: String?

  public init(identityToken: Data, fullName: String?) {
    self.identityToken = identityToken
    self.fullName = fullName
  }
}

public enum AuthServiceError: Error, Equatable, Sendable {
  case invalidAppleCredential
}

struct AppleSignInRequest: Encodable, Sendable {
  let identityToken: String
  let fullName: String?
}

struct EmptyRequest: Encodable, Sendable {}
