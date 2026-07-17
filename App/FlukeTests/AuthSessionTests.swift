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
        identityToken: Data("signed.jwt".utf8),
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

    await session.signIn(credential: .init(identityToken: Data(), fullName: nil))

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
    await session.signIn(credential: .init(identityToken: Data("jwt".utf8), fullName: nil))

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
    await session.signIn(credential: .init(identityToken: Data("jwt".utf8), fullName: nil))

    await session.deleteAccount()

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
