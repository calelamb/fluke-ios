import AuthenticationServices
import FlukeReleaseB
import Foundation
import Testing

@testable import Fluke

@MainActor
struct AppleAuthorizationFlowTests {
  @Test("Authorization request receives a one-use nonce and Apple scopes")
  func oneUseNonce() throws {
    let nonce = "abcdefghijklmnopqrstuvwxyzABCDEF"
    let flow = AppleAuthorizationFlow(nonceGenerator: { nonce })
    let request = ASAuthorizationAppleIDProvider().createRequest()

    flow.configure(request)

    #expect(request.nonce == nonce)
    #expect(Set(request.requestedScopes ?? []) == [.fullName, .email])
    let credential = try flow.consume(
      identityToken: Data("signed.jwt".utf8),
      authorizationCode: Data("one-use-code".utf8),
      fullName: "Cale Lamb"
    ).get()
    #expect(credential.nonce == nonce)
    #expect(!flow.hasPendingNonce)
    #expect(throws: AuthPresentationError.invalidAppleCredential) {
      try flow.consume(
        identityToken: Data("signed.jwt".utf8),
        authorizationCode: Data("replay-code".utf8),
        fullName: nil
      ).get()
    }
  }

  @Test("Cancellation and malformed results clear pending nonce")
  func cancellationClearsNonce() throws {
    let flow = AppleAuthorizationFlow(nonceGenerator: {
      "abcdefghijklmnopqrstuvwxyzABCDEF"
    })
    flow.configure(ASAuthorizationAppleIDProvider().createRequest())
    flow.cancel()
    #expect(!flow.hasPendingNonce)

    flow.configure(ASAuthorizationAppleIDProvider().createRequest())
    #expect(throws: AuthPresentationError.invalidAppleCredential) {
      try flow.consume(
        identityToken: Data("jwt".utf8), authorizationCode: nil, fullName: nil
      ).get()
    }
    #expect(!flow.hasPendingNonce)
  }

  @Test("Production nonce has at least 32 random bytes encoded as unpadded base64url")
  func secureNonceShape() throws {
    let first = try AppleAuthorizationFlow.secureNonce()
    let second = try AppleAuthorizationFlow.secureNonce()

    #expect(first.count >= 43)
    #expect(first.count <= 256)
    #expect(first != second)
    #expect(!first.contains("="))
    #expect(
      first.unicodeScalars.allSatisfy {
        CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
      })
  }

  @Test("Apple cancellation is recognized without exposing the provider error")
  func recognizesCancellation() {
    let canceled = Result<ASAuthorization, Error>.failure(
      ASAuthorizationError(.canceled)
    )
    let failed = Result<ASAuthorization, Error>.failure(
      ASAuthorizationError(.failed)
    )

    #expect(AppleAuthorizationAdapter.isCancellation(canceled))
    #expect(!AppleAuthorizationAdapter.isCancellation(failed))
  }
}
