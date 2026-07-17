import FlukeKit
import Foundation

public protocol AuthServiceProtocol: Sendable {
  func signIn(credential: AppleCredential) async throws -> AuthenticatedUser
  func currentUser() async throws -> AuthenticatedUser
  func signOut() async throws
  func deleteAccount(credential: AppleCredential) async throws
}

public struct AuthService: AuthServiceProtocol, Sendable {
  private let api: APIClient

  public init(api: APIClient) {
    self.api = api
  }

  public func signIn(credential: AppleCredential) async throws -> AuthenticatedUser {
    let values = try validatedCredential(credential)
    let name = credential.fullName?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard name == nil || isValid(name ?? "", maximum: 120) else {
      throw AuthServiceError.invalidAppleCredential
    }
    let response: AppleSignInResponse = try await api.post(
      APIRequest(path: ReleaseBEndpoint.authApple),
      body: AppleSignInRequest(
        authorizationCode: values.authorizationCode,
        identityToken: values.identityToken,
        nonce: credential.nonce,
        fullName: name?.isEmpty == false ? name : nil
      )
    )
    let cookieToken = try api.validatedCSRFCookieValue(
      for: APIRequest(path: ReleaseBEndpoint.authApple)
    )
    guard response.csrfToken == cookieToken else { throw APIError.malformedResponse }
    return try validated(response.user)
  }

  public func currentUser() async throws -> AuthenticatedUser {
    let response: CurrentObserverResponse = try await api.get(
      APIRequest(path: ReleaseBEndpoint.authMe)
    )
    guard response.userId == response.id else { throw APIError.malformedResponse }
    return try validated(
      AuthenticatedUser(
        id: response.id,
        email: response.email,
        displayName: response.displayName,
        role: response.role
      ))
  }

  public func signOut() async throws {
    try await api.postOKWithCSRF(APIRequest(path: ReleaseBEndpoint.authLogout))
    api.clearCookies()
  }

  public func deleteAccount(credential: AppleCredential) async throws {
    let values = try validatedCredential(credential)
    try await api.deleteOKWithCSRF(
      APIRequest(path: ReleaseBEndpoint.authAccount),
      body: DeleteAccountRequest(
        authorizationCode: values.authorizationCode,
        identityToken: values.identityToken,
        nonce: credential.nonce
      )
    )
    api.clearCookies()
  }

  private func validated(_ user: AuthenticatedUser) throws -> AuthenticatedUser {
    guard isValid(user.id, maximum: 200),
      user.email == nil
        || (isValid(user.email ?? "", maximum: 320)
          && EmailAddressValidator.isValid(user.email ?? "")),
      user.role == "OBSERVER"
    else {
      throw APIError.malformedResponse
    }
    let displayName = user.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard displayName == nil || isValid(displayName ?? "", maximum: 200) else {
      throw APIError.malformedResponse
    }
    return AuthenticatedUser(
      id: user.id.trimmingCharacters(in: .whitespacesAndNewlines),
      email: user.email?.trimmingCharacters(in: .whitespacesAndNewlines),
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

  private func validatedCredential(
    _ credential: AppleCredential
  ) throws -> (authorizationCode: String, identityToken: String) {
    guard let authorizationCode = String(data: credential.authorizationCode, encoding: .utf8),
      let identityToken = String(data: credential.identityToken, encoding: .utf8),
      credential.isStructurallyValid
    else {
      throw AuthServiceError.invalidAppleCredential
    }
    return (authorizationCode, identityToken)
  }
}
