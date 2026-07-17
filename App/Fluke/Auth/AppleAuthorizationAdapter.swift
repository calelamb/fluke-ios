import AuthenticationServices
import Foundation

struct AppleAuthorizationPayload {
  let authorizationCode: Data?
  let identityToken: Data?
  let fullName: String?
}

enum AppleAuthorizationAdapter {
  static func payload(
    from result: Result<ASAuthorization, Error>
  ) -> Result<AppleAuthorizationPayload, AuthPresentationError> {
    guard case .success(let authorization) = result,
      let apple = authorization.credential as? ASAuthorizationAppleIDCredential
    else {
      return .failure(.invalidAppleCredential)
    }
    let formatter = PersonNameComponentsFormatter()
    let name = apple.fullName.map(formatter.string(from:))
    return .success(
      AppleAuthorizationPayload(
        authorizationCode: apple.authorizationCode,
        identityToken: apple.identityToken,
        fullName: name?.isEmpty == false ? name : nil
      ))
  }

  static func isCancellation(_ result: Result<ASAuthorization, Error>) -> Bool {
    guard case .failure(let error) = result,
      let authorizationError = error as? ASAuthorizationError
    else { return false }
    return authorizationError.code == .canceled
  }
}
