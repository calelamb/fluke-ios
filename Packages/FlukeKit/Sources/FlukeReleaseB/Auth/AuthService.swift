import FlukeKit
import Foundation

public protocol AuthServiceProtocol: Sendable {
  func signIn(credential: AppleCredential) async throws -> AuthenticatedUser
  func currentUser() async throws -> AuthenticatedUser
  func signOut() async throws
  func deleteAccount() async throws
}

public struct AuthService: AuthServiceProtocol, Sendable {
  private let api: APIClient

  public init(api: APIClient) {
    self.api = api
  }

  public func signIn(credential: AppleCredential) async throws -> AuthenticatedUser {
    guard let token = String(data: credential.identityToken, encoding: .utf8),
      !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw AuthServiceError.invalidAppleCredential
    }
    let name = credential.fullName?.trimmingCharacters(in: .whitespacesAndNewlines)
    let user: AuthenticatedUser = try await api.post(
      APIRequest(path: ReleaseBEndpoint.authApple),
      body: AppleSignInRequest(
        identityToken: token,
        fullName: name?.isEmpty == false ? name : nil
      )
    )
    return try validated(user)
  }

  public func currentUser() async throws -> AuthenticatedUser {
    let user: AuthenticatedUser = try await api.get(
      APIRequest(path: ReleaseBEndpoint.authMe)
    )
    return try validated(user)
  }

  public func signOut() async throws {
    try await api.postNoContent(
      APIRequest(path: ReleaseBEndpoint.authLogout),
      body: EmptyRequest()
    )
    api.clearCookies()
  }

  public func deleteAccount() async throws {
    try await api.deleteNoContent(APIRequest(path: ReleaseBEndpoint.authAccount))
    api.clearCookies()
  }

  private func validated(_ user: AuthenticatedUser) throws -> AuthenticatedUser {
    guard isValid(user.id, maximum: 200),
      isValid(user.email, maximum: 320),
      EmailAddressValidator.isValid(user.email),
      isValid(user.role, maximum: 100)
    else {
      throw APIError.malformedResponse
    }
    let displayName = user.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard displayName == nil || isValid(displayName ?? "", maximum: 200) else {
      throw APIError.malformedResponse
    }
    return AuthenticatedUser(
      id: user.id.trimmingCharacters(in: .whitespacesAndNewlines),
      email: user.email.trimmingCharacters(in: .whitespacesAndNewlines),
      displayName: displayName,
      role: user.role.trimmingCharacters(in: .whitespacesAndNewlines)
    )
  }

  private func isValid(_ value: String, maximum: Int) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return !trimmed.isEmpty
      && trimmed.count <= maximum
      && trimmed.unicodeScalars.allSatisfy {
        !CharacterSet.controlCharacters.contains($0)
      }
  }
}
