import AuthenticationServices
import FlukeReleaseB
import Foundation
import Security

@MainActor
final class AppleAuthorizationFlow {
  typealias NonceGenerator = @MainActor () throws -> String

  private let nonceGenerator: NonceGenerator
  private var pendingNonce: String?

  init(nonceGenerator: @escaping NonceGenerator = AppleAuthorizationFlow.secureNonce) {
    self.nonceGenerator = nonceGenerator
  }

  var hasPendingNonce: Bool { pendingNonce != nil }

  func configure(_ request: ASAuthorizationAppleIDRequest) {
    pendingNonce = nil
    request.requestedScopes = [.fullName, .email]
    guard let nonce = try? nonceGenerator(), Self.isValidNonce(nonce) else {
      request.nonce = nil
      return
    }
    pendingNonce = nonce
    request.nonce = nonce
  }

  func consume(
    identityToken: Data?,
    authorizationCode: Data?,
    fullName: String?
  ) -> Result<AppleCredential, AuthPresentationError> {
    let nonce = pendingNonce
    pendingNonce = nil
    guard let nonce, let identityToken, let authorizationCode else {
      return .failure(.invalidAppleCredential)
    }
    let credential = AppleCredential(
      authorizationCode: authorizationCode,
      identityToken: identityToken,
      nonce: nonce,
      fullName: fullName
    )
    guard credential.isStructurallyValid else {
      return .failure(.invalidAppleCredential)
    }
    return .success(credential)
  }

  func credential(
    from result: Result<ASAuthorization, Error>
  ) -> Result<AppleCredential, AuthPresentationError> {
    switch AppleAuthorizationAdapter.payload(from: result) {
    case .success(let payload):
      return consume(
        identityToken: payload.identityToken,
        authorizationCode: payload.authorizationCode,
        fullName: payload.fullName
      )
    case .failure(let error):
      cancel()
      return .failure(error)
    }
  }

  func cancel() { pendingNonce = nil }

  nonisolated static func secureNonce() throws -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
      throw AuthPresentationError.unavailable("Fluke couldn't start secure Apple sign in.")
    }
    return Data(bytes).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  private static func isValidNonce(_ nonce: String) -> Bool {
    nonce.count >= 32 && nonce.count <= 256
      && nonce.unicodeScalars.allSatisfy {
        CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
      }
  }
}
