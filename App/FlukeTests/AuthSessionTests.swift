import FlukeKit
import FlukeReleaseB
import Foundation
import Testing

@testable import Fluke

@MainActor
struct AuthSessionTests {
  @Test("A valid Apple credential becomes an authenticated observer")
  func signIn() async {
    let session = AuthSession(
      service: AuthServiceSpy(signInResult: .success(.fixture)),
      hints: MemorySessionHintStore()
    )

    await session.signIn(
      credential: AppleCredential(
        identityToken: Data("signed.jwt".utf8),
        fullName: "Cale Lamb"
      )
    )

    #expect(session.state == .signedIn(.fixture))
  }

  @Test("Missing token fails closed")
  func missingToken() async {
    let session = AuthSession(service: AuthServiceSpy(), hints: MemorySessionHintStore())

    await session.signIn(credential: .init(identityToken: Data(), fullName: nil))

    #expect(session.state == .signedOut(error: .invalidAppleCredential))
  }

  @Test("Unauthorized restore becomes signed out")
  func unauthorizedRestore() async {
    let session = AuthSession(
      service: AuthServiceSpy(currentUserResult: .failure(APIError.unauthorized)),
      hints: MemorySessionHintStore()
    )

    await session.restore()

    #expect(session.state == .signedOut(error: nil))
  }

  @Test("A retryable restore failure preserves a known signed-in user")
  func restoreFailurePreservesUser() async {
    let service = AuthServiceSpy(
      signInResult: .success(.fixture),
      currentUserResult: .failure(APIError.offline)
    )
    let session = AuthSession(service: service, hints: MemorySessionHintStore())
    await session.signIn(credential: .init(identityToken: Data("jwt".utf8), fullName: nil))

    await session.restore()

    #expect(session.state == .signedIn(.fixture))
    #expect(session.notice == .retryable("You're offline."))
  }

  @Test("Logout clears the server session but retains only a reauthentication hint")
  func logout() async throws {
    let service = AuthServiceSpy(signInResult: .success(.fixture))
    let hints = MemorySessionHintStore()
    let session = AuthSession(service: service, hints: hints)
    await session.signIn(credential: .init(identityToken: Data("jwt".utf8), fullName: nil))

    await session.signOut()

    #expect(session.state == .signedOut(error: nil))
    #expect(await service.signOutCallCount == 1)
    #expect(try await hints.hasReauthenticationHint())
  }

  @Test("Failed deletion preserves authenticated state and local hints")
  func failedDeletion() async throws {
    let service = AuthServiceSpy(
      signInResult: .success(.fixture),
      deleteResult: .failure(APIError.offline)
    )
    let hints = MemorySessionHintStore()
    let associations = AccountAssociationSpy()
    let session = AuthSession(service: service, hints: hints, accountAssociations: associations)
    await session.signIn(credential: .init(identityToken: Data("jwt".utf8), fullName: nil))

    await session.deleteAccount()

    #expect(session.state == .signedIn(.fixture))
    #expect(session.notice == .retryable("You're offline."))
    #expect(try await hints.hasReauthenticationHint())
    #expect(await associations.clearCallCount == 0)
  }

  @Test("A 204 deletion clears local authenticated state and hints")
  func successfulDeletion() async throws {
    let service = AuthServiceSpy(signInResult: .success(.fixture))
    let hints = MemorySessionHintStore()
    let associations = AccountAssociationSpy()
    let session = AuthSession(service: service, hints: hints, accountAssociations: associations)
    await session.signIn(credential: .init(identityToken: Data("jwt".utf8), fullName: nil))

    await session.deleteAccount()

    #expect(session.state == .signedOut(error: nil))
    #expect(try await hints.hasReauthenticationHint() == false)
    #expect(await associations.clearCallCount == 1)
  }
}

private actor AccountAssociationSpy: AccountAssociationClearing {
  private(set) var clearCallCount = 0

  func clearAccountAssociation() async {
    clearCallCount += 1
  }
}

private actor AuthServiceSpy: AuthServiceProtocol {
  private let signInResult: Result<AuthenticatedUser, Error>
  private let currentUserResult: Result<AuthenticatedUser, Error>
  private let signOutResult: Result<Void, Error>
  private let deleteResult: Result<Void, Error>
  private(set) var signOutCallCount = 0

  init(
    signInResult: Result<AuthenticatedUser, Error> = .failure(APIError.transport),
    currentUserResult: Result<AuthenticatedUser, Error> = .failure(APIError.transport),
    signOutResult: Result<Void, Error> = .success(()),
    deleteResult: Result<Void, Error> = .success(())
  ) {
    self.signInResult = signInResult
    self.currentUserResult = currentUserResult
    self.signOutResult = signOutResult
    self.deleteResult = deleteResult
  }

  func signIn(credential: AppleCredential) async throws -> AuthenticatedUser {
    try signInResult.get()
  }

  func currentUser() async throws -> AuthenticatedUser {
    try currentUserResult.get()
  }

  func signOut() async throws {
    signOutCallCount += 1
    try signOutResult.get()
  }

  func deleteAccount() async throws {
    try deleteResult.get()
  }
}

private actor MemorySessionHintStore: SessionHintStore {
  private var value = false

  func hasReauthenticationHint() async throws -> Bool { value }
  func saveReauthenticationHint() async throws { value = true }
  func clear() async throws { value = false }
}

extension AuthenticatedUser {
  fileprivate static let fixture = AuthenticatedUser(
    id: "observer-1",
    email: "cale@example.com",
    displayName: "Cale Lamb",
    role: "observer"
  )
}
