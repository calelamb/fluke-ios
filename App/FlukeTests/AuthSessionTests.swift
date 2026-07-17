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
      hints: MemorySessionHintStore(),
      accountAssociations: AccountAssociationSpy()
    )

    await session.signIn(
      credential: AppleCredential(
        authorizationCode: Data("code".utf8),
        identityToken: Data("signed.jwt".utf8),
        nonce: String(repeating: "n", count: 32),
        fullName: "Cale Lamb"
      )
    )

    #expect(session.state == .signedIn(.fixture))
  }

  @Test("Missing token fails closed")
  func missingToken() async {
    let session = AuthSession(
      service: AuthServiceSpy(),
      hints: MemorySessionHintStore(),
      accountAssociations: AccountAssociationSpy()
    )

    await session.signIn(credential: .invalidFixture)

    #expect(session.state == .signedOut(error: .invalidAppleCredential))
  }

  @Test("Unauthorized restore becomes signed out")
  func unauthorizedRestore() async {
    let session = AuthSession(
      service: AuthServiceSpy(currentUserResult: .failure(APIError.unauthorized)),
      hints: MemorySessionHintStore(),
      accountAssociations: AccountAssociationSpy()
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
    let session = AuthSession(
      service: service,
      hints: MemorySessionHintStore(),
      accountAssociations: AccountAssociationSpy()
    )
    await session.signIn(credential: .validFixture)

    await session.restore()

    #expect(session.state == .signedIn(.fixture))
    #expect(session.notice == .retryable("You're offline."))
  }

  @Test("Logout clears the server session but retains only a reauthentication hint")
  func logout() async throws {
    let service = AuthServiceSpy(signInResult: .success(.fixture))
    let hints = MemorySessionHintStore()
    let session = AuthSession(
      service: service,
      hints: hints,
      accountAssociations: AccountAssociationSpy()
    )
    await session.signIn(credential: .validFixture)

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
    await session.signIn(credential: .validFixture)

    await session.deleteAccount(credential: .validFixture)

    #expect(session.state == .signedIn(.fixture))
    #expect(
      session.notice
        == .retryable(
          "Your account was not deleted. You're offline. Confirm with Apple again to retry."
        )
    )
    #expect(try await hints.hasReauthenticationHint())
    #expect(await associations.clearCallCount == 0)
  }

  @Test("Deletion rejects a malformed fresh credential without calling the service")
  func invalidDeletionCredential() async {
    let service = AuthServiceSpy(signInResult: .success(.fixture))
    let session = AuthSession(
      service: service,
      hints: MemorySessionHintStore(),
      accountAssociations: AccountAssociationSpy()
    )
    await session.signIn(credential: .validFixture)

    await session.deleteAccount(credential: .invalidFixture)

    #expect(session.state == .signedIn(.fixture))
    #expect(session.notice == .invalidAppleCredential)
    #expect(await service.deleteCallCount == 0)
  }

  @Test("Malformed Apple presentation helpers preserve or expire the intended session")
  func invalidPresentationHelpers() async {
    let session = AuthSession(
      service: AuthServiceSpy(signInResult: .success(.fixture)),
      hints: MemorySessionHintStore(),
      accountAssociations: AccountAssociationSpy()
    )
    session.reportInvalidCredential()
    #expect(session.notice == nil)

    await session.signIn(credential: .validFixture)
    session.reportInvalidCredential()
    #expect(session.state == .signedIn(.fixture))
    #expect(session.notice == .invalidAppleCredential)

    session.expireWithInvalidCredential()
    #expect(session.state == .signedOut(error: .invalidAppleCredential))
    #expect(session.notice == nil)
  }

  @Test("A successful reauthenticated deletion clears local authenticated state and hints")
  func successfulDeletion() async throws {
    let service = AuthServiceSpy(signInResult: .success(.fixture))
    let hints = MemorySessionHintStore()
    let associations = AccountAssociationSpy()
    let session = AuthSession(service: service, hints: hints, accountAssociations: associations)
    await session.signIn(credential: .validFixture)

    await session.deleteAccount(credential: .validFixture)

    #expect(session.state == .signedOut(error: nil))
    #expect(try await hints.hasReauthenticationHint() == false)
    #expect(await associations.clearCallCount == 1)
  }

  @Test("A failed post-204 queue cleanup signs out and reports local recovery")
  func failedAssociationCleanup() async throws {
    let service = AuthServiceSpy(signInResult: .success(.fixture))
    let hints = MemorySessionHintStore()
    let associations = AccountAssociationSpy(result: .failure(TestCleanupError.failed))
    let session = AuthSession(
      service: service,
      hints: hints,
      accountAssociations: associations
    )
    await session.signIn(credential: .validFixture)

    await session.deleteAccount(credential: .validFixture)

    #expect(
      session.state
        == .signedOut(
          error: .unavailable(
            "Your account was deleted, but queued sightings still need local cleanup."
          )
        )
    )
    #expect(try await hints.hasReauthenticationHint() == false)
    #expect(await associations.clearCallCount == 1)
  }

  @Test("The durable submission queue bridge exposes queued sightings and clears account email")
  func durableSubmissionQueueBridge() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let queue = try SubmissionQueue(directory: directory, inMemory: true)
    let payload = SubmissionPayload(
      latitude: 48.5, longitude: -123.1,
      observedAt: Date(timeIntervalSince1970: 1_700_000_000), groupSize: 2,
      notes: nil, locationName: "Lime Kiln", observerEmail: "observer@example.com", photoCount: 1
    )
    _ = try await queue.enqueue(
      payload: payload,
      photos: [ProcessedPhoto(bytes: Data(repeating: 1, count: 8), fileName: "photo.jpg")]
    )
    let bridge = DeferredSubmissionQueueBridge(queue: queue)

    #expect(await bridge.queuedEntries().map(\.locationName) == ["Lime Kiln"])
    try await bridge.clearAccountAssociation()
    #expect(try await queue.list().first?.payload.observerEmail == nil)
  }
}

private actor AccountAssociationSpy: AccountAssociationClearing {
  private let result: Result<Void, Error>
  private(set) var clearCallCount = 0

  init(result: Result<Void, Error> = .success(())) {
    self.result = result
  }

  func clearAccountAssociation() async throws {
    clearCallCount += 1
    try result.get()
  }
}

private enum TestCleanupError: Error {
  case failed
}

private actor AuthServiceSpy: AuthServiceProtocol {
  private let signInResult: Result<AuthenticatedUser, Error>
  private let currentUserResult: Result<AuthenticatedUser, Error>
  private let signOutResult: Result<Void, Error>
  private let deleteResult: Result<Void, Error>
  private(set) var signOutCallCount = 0
  private(set) var deleteCallCount = 0

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

  func deleteAccount(credential: AppleCredential) async throws {
    deleteCallCount += 1
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
    role: "OBSERVER"
  )
}

extension AppleCredential {
  fileprivate static let validFixture = AppleCredential(
    authorizationCode: Data("code".utf8), identityToken: Data("jwt".utf8),
    nonce: String(repeating: "n", count: 32), fullName: nil
  )
  fileprivate static let invalidFixture = AppleCredential(
    authorizationCode: Data(), identityToken: Data(), nonce: "", fullName: nil
  )
}
