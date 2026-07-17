import AuthenticationServices
import FlukeReleaseB
import Foundation

enum AppleAuthorizationAdapter {
  static func configure(_ request: ASAuthorizationAppleIDRequest) {
    request.requestedScopes = [.fullName, .email]
  }

  static func credential(
    from result: Result<ASAuthorization, Error>
  ) -> Result<AppleCredential, AuthPresentationError> {
    guard case .success(let authorization) = result,
      let apple = authorization.credential as? ASAuthorizationAppleIDCredential,
      let token = apple.identityToken,
      let tokenValue = String(data: token, encoding: .utf8),
      !tokenValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      return .failure(.invalidAppleCredential)
    }

    let formatter = PersonNameComponentsFormatter()
    let fullName = apple.fullName.map(formatter.string(from:))
    return .success(
      AppleCredential(
        identityToken: token,
        fullName: fullName?.isEmpty == false ? fullName : nil
      )
    )
  }
}
