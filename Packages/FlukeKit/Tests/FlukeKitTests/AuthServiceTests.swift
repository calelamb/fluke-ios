import Foundation
import Testing

@testable import FlukeKit
@testable import FlukeReleaseB

struct AuthServiceTests {
  @Test("Apple sign in sends the strict API credential and decodes its wrapper")
  func appleSignInContract() async throws {
    let harness = try AuthHarness(
      body:
        #"{"csrfToken":"abcdefghijklmnopqrstuvwxyzABCDEF","user":{"id":"observer-1","email":null,"displayName":"Cale Lamb","role":"OBSERVER"}}"#
    )
    let credential = AppleCredential(
      authorizationCode: Data("one-use-code".utf8),
      identityToken: Data("signed.jwt".utf8),
      nonce: "abcdefghijklmnopqrstuvwxyzABCDEF",
      fullName: " Cale Lamb "
    )

    let user = try await harness.service.signIn(credential: credential)

    #expect(user.id == "observer-1")
    #expect(user.email == nil)
    #expect(user.role == "OBSERVER")
    let request = try #require(await harness.transport.lastRequest)
    let body = try #require(request.httpBody)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(Set(json.keys) == ["authorizationCode", "identityToken", "nonce", "fullName"])
    #expect(json["authorizationCode"] as? String == "one-use-code")
    #expect(json["identityToken"] as? String == "signed.jwt")
    #expect(json["nonce"] as? String == "abcdefghijklmnopqrstuvwxyzABCDEF")
    #expect(json["fullName"] as? String == "Cale Lamb")
  }

  @Test(
    "Credential bounds fail before transport",
    arguments: [
      AppleCredential(
        authorizationCode: Data(), identityToken: Data("jwt".utf8),
        nonce: String(repeating: "n", count: 32), fullName: nil),
      AppleCredential(
        authorizationCode: Data("code".utf8), identityToken: Data(),
        nonce: String(repeating: "n", count: 32), fullName: nil),
      AppleCredential(
        authorizationCode: Data("code".utf8), identityToken: Data("jwt".utf8), nonce: "short",
        fullName: nil),
      AppleCredential(
        authorizationCode: Data(repeating: 1, count: 4_097), identityToken: Data("jwt".utf8),
        nonce: String(repeating: "n", count: 32), fullName: nil),
      AppleCredential(
        authorizationCode: Data("code".utf8), identityToken: Data(repeating: 1, count: 16_385),
        nonce: String(repeating: "n", count: 32), fullName: nil),
      AppleCredential(
        authorizationCode: Data("code".utf8), identityToken: Data("jwt".utf8),
        nonce: String(repeating: "n", count: 257), fullName: nil),
      AppleCredential(
        authorizationCode: Data("code".utf8), identityToken: Data("jwt".utf8),
        nonce: String(repeating: "n", count: 31) + "!", fullName: nil),
      AppleCredential(
        authorizationCode: Data("code".utf8), identityToken: Data("jwt".utf8),
        nonce: String(repeating: "n", count: 32), fullName: String(repeating: "n", count: 121)),
      AppleCredential(
        authorizationCode: Data("code".utf8), identityToken: Data("jwt".utf8),
        nonce: String(repeating: "n", count: 32), fullName: "Unsafe\nName"),
    ])
  func rejectsMalformedCredential(credential: AppleCredential) async throws {
    let harness = try AuthHarness(body: "{}", csrf: String(repeating: "c", count: 32))
    await #expect(throws: AuthServiceError.invalidAppleCredential) {
      try await harness.service.signIn(credential: credential)
    }
    #expect(await harness.transport.lastRequest == nil)
  }

  @Test(
    "Sign-in response rejects wrong roles and malformed wrappers",
    arguments: [
      #"{"csrfToken":"abcdefghijklmnopqrstuvwxyzABCDEF","user":{"id":"observer-1","email":null,"displayName":null,"role":"ADMIN"}}"#,
      #"{"csrfToken":"abcdefghijklmnopqrstuvwxyzABCDEF","user":{"id":"observer-1","email":null,"displayName":null,"role":"OBSERVER"},"extra":true}"#,
      #"{"csrfToken":"abcdefghijklmnopqrstuvwxyzABCDEF","user":{"id":"observer-1","email":null,"displayName":null,"role":"OBSERVER","extra":true}}"#,
      #"{"user":{"id":"observer-1","email":null,"displayName":null,"role":"OBSERVER"}}"#,
    ])
  func rejectsMalformedSignInResponse(body: String) async throws {
    let harness = try AuthHarness(body: body)
    await #expect(throws: APIError.self) {
      try await harness.service.signIn(credential: .validFixture)
    }
  }

  @Test("Sign-in rejects a response token that differs from the secure cookie")
  func rejectsMismatchedCSRF() async throws {
    let harness = try AuthHarness(
      body:
        #"{"csrfToken":"responseTokenResponseToken12345678","user":{"id":"observer-1","email":null,"displayName":null,"role":"OBSERVER"}}"#,
      csrf: "cookieTokenCookieTokenCookieToken12"
    )
    await #expect(throws: APIError.malformedResponse) {
      try await harness.service.signIn(credential: .validFixture)
    }
  }

  @Test("Restore decodes a nullable-email observer DTO")
  func restoreNullableEmail() async throws {
    let harness = try AuthHarness(
      body:
        #"{"id":"observer-1","email":null,"displayName":null,"role":"OBSERVER","userId":"observer-1"}"#
    )
    let user = try await harness.service.currentUser()
    #expect(user.email == nil)
  }

  @Test("Current observer maps unauthorized without inventing a user")
  func currentUserUnauthorized() async throws {
    let harness = try AuthHarness(status: 401, body: "")
    await #expect(throws: APIError.unauthorized) { try await harness.service.currentUser() }
  }

  @Test("Logout uses CSRF and accepts only 200 ok")
  func logoutContract() async throws {
    let harness = try AuthHarness(body: #"{"ok":true}"#)
    try await harness.service.signOut()
    let request = try #require(await harness.transport.lastRequest)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path == ReleaseBEndpoint.authLogout)
    #expect(request.value(forHTTPHeaderField: "x-fluke-csrf") == "abcdefghijklmnopqrstuvwxyzABCDEF")
  }

  @Test("Deletion sends a fresh strict credential body with CSRF")
  func deletionContract() async throws {
    let harness = try AuthHarness(body: #"{"ok":true}"#)
    try await harness.service.deleteAccount(credential: .validFixture)
    let request = try #require(await harness.transport.lastRequest)
    #expect(request.httpMethod == "DELETE")
    #expect(request.url?.path == ReleaseBEndpoint.authAccount)
    #expect(request.value(forHTTPHeaderField: "x-fluke-csrf") == "abcdefghijklmnopqrstuvwxyzABCDEF")
    let body = try #require(request.httpBody)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
    #expect(Set(json.keys) == ["authorizationCode", "identityToken", "nonce"])
  }

  @Test(
    "Protected methods reject non-200 or non-ok responses",
    arguments: [
      (204, ""), (201, #"{"ok":true}"#), (200, #"{"ok":false}"#),
      (200, #"{"ok":true,"extra":1}"#),
    ])
  func rejectsInvalidOK(status: Int, body: String) async throws {
    let harness = try AuthHarness(status: status, body: body)
    await #expect(throws: APIError.self) { try await harness.service.signOut() }
  }
}

private struct AuthHarness {
  let transport: AuthRecordingTransport
  let service: AuthService

  init(status: Int = 200, body: String, csrf: String = "abcdefghijklmnopqrstuvwxyzABCDEF") throws {
    let storage = HTTPCookieStorage.sharedCookieStorage(
      forGroupContainerIdentifier: UUID().uuidString)
    let cookie = try #require(
      HTTPCookie(properties: [
        .domain: "api.fluke.test", .path: "/", .name: "fluke_csrf", .value: csrf,
        .secure: "TRUE",
      ]))
    storage.setCookie(cookie)
    let transport = AuthRecordingTransport(status: status, body: body)
    self.transport = transport
    service = AuthService(
      api: APIClient(
        baseURL: try #require(URL(string: "https://api.fluke.test")),
        transport: transport,
        cookieStorage: storage
      ))
  }
}

private actor AuthRecordingTransport: HTTPTransport {
  let status: Int
  let body: Data
  private(set) var lastRequest: URLRequest?
  init(status: Int, body: String) {
    self.status = status
    self.body = Data(body.utf8)
  }
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    lastRequest = request
    return (
      body,
      HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    )
  }
}

extension AppleCredential {
  fileprivate static let validFixture = AppleCredential(
    authorizationCode: Data("one-use-code".utf8),
    identityToken: Data("signed.jwt".utf8),
    nonce: "abcdefghijklmnopqrstuvwxyzABCDEF",
    fullName: nil
  )
}
