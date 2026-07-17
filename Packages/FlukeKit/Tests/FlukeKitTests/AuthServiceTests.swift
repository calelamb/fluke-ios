import Foundation
import Testing

@testable import FlukeKit
@testable import FlukeReleaseB

struct AuthServiceTests {
  @Test("Apple sign in sends the typed credential and decodes the observer")
  func appleSignIn() async throws {
    let transport = RecordingTransport(
      status: 200,
      body:
        #"{"id":"observer-1","email":"cale@example.com","displayName":"Cale Lamb","role":"observer"}"#
    )
    let service = AuthService(
      api: APIClient(
        baseURL: try #require(URL(string: "https://api.fluke.test")),
        transport: transport
      ))

    let user = try await service.signIn(
      credential: AppleCredential(
        identityToken: Data("signed.jwt".utf8),
        fullName: "Cale Lamb"
      )
    )

    #expect(user.id == "observer-1")
    #expect(user.displayName == "Cale Lamb")
    let request = try #require(await transport.lastRequest)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path == ReleaseBEndpoint.authApple)
    let body = try #require(request.httpBody)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
    #expect(json == ["identityToken": "signed.jwt", "fullName": "Cale Lamb"])
  }

  @Test("Current observer maps an unauthorized response without inventing a user")
  func currentUserUnauthorized() async throws {
    let service = AuthService(
      api: APIClient(
        baseURL: try #require(URL(string: "https://api.fluke.test")),
        transport: RecordingTransport(status: 401, body: "")
      ))

    await #expect(throws: APIError.unauthorized) {
      try await service.currentUser()
    }
  }

  @Test("Malformed observer identity fails closed")
  func malformedObserver() async throws {
    let service = AuthService(
      api: APIClient(
        baseURL: try #require(URL(string: "https://api.fluke.test")),
        transport: RecordingTransport(
          status: 200,
          body: #"{"id":" ","email":"cale@example.com","displayName":null,"role":"observer"}"#
        )
      ))

    await #expect(throws: APIError.malformedResponse) {
      try await service.currentUser()
    }
  }

  @Test("Account deletion requires the server's 204 response")
  func accountDeletionRequiresNoContent() async throws {
    let accepted = RecordingTransport(status: 204, body: "")
    let acceptedService = AuthService(
      api: APIClient(
        baseURL: try #require(URL(string: "https://api.fluke.test")),
        transport: accepted
      ))

    try await acceptedService.deleteAccount()
    let request = try #require(await accepted.lastRequest)
    #expect(request.httpMethod == "DELETE")
    #expect(request.url?.path == ReleaseBEndpoint.authAccount)

    let rejectedService = AuthService(
      api: APIClient(
        baseURL: try #require(URL(string: "https://api.fluke.test")),
        transport: RecordingTransport(status: 200, body: "{}")
      ))
    await #expect(throws: APIError.malformedResponse) {
      try await rejectedService.deleteAccount()
    }
  }
}

private actor RecordingTransport: HTTPTransport {
  private let status: Int
  private let body: Data
  private(set) var lastRequest: URLRequest?

  init(status: Int, body: String) {
    self.status = status
    self.body = Data(body.utf8)
  }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    lastRequest = request
    let response = try #require(
      HTTPURLResponse(
        url: request.url ?? URL(fileURLWithPath: "/"),
        statusCode: status,
        httpVersion: nil,
        headerFields: nil
      ))
    return (body, response)
  }
}
