import FlukeKit
import FlukeReleaseB
import Foundation
import Observation

enum AuthPresentationError: Error, Equatable {
  case invalidAppleCredential
  case retryable(String)
  case unavailable(String)
}

nonisolated protocol AccountAssociationClearing: Sendable {
  func clearAccountAssociation() async throws
}

@MainActor
@Observable
final class AuthSession {
  enum State: Equatable {
    case restoring
    case signedOut(error: AuthPresentationError?)
    case signingIn
    case signedIn(AuthenticatedUser)
  }

  private(set) var state: State = .restoring
  private(set) var notice: AuthPresentationError?
  private(set) var isAccountMutationInFlight = false

  private let service: any AuthServiceProtocol
  private let hints: any SessionHintStore
  private let accountAssociations: any AccountAssociationClearing
  private var accountMutationGeneration: UInt64 = 0
  private var activeAccountMutationGeneration: UInt64?

  init(
    service: any AuthServiceProtocol,
    hints: any SessionHintStore,
    accountAssociations: any AccountAssociationClearing
  ) {
    self.service = service
    self.hints = hints
    self.accountAssociations = accountAssociations
  }

  func restore() async {
    guard !isAccountMutationInFlight else { return }
    let knownUser = signedInUser
    if knownUser == nil { state = .restoring }
    notice = nil
    do {
      state = .signedIn(try await service.currentUser())
    } catch APIError.unauthorized {
      state = .signedOut(error: nil)
    } catch {
      let presentation = presentationError(for: error)
      if let knownUser {
        state = .signedIn(knownUser)
        notice = presentation
      } else {
        state = .signedOut(error: presentation)
      }
    }
  }

  func signIn(credential: AppleCredential) async {
    guard !isAccountMutationInFlight else { return }
    guard credential.isStructurallyValid else {
      state = .signedOut(error: .invalidAppleCredential)
      return
    }

    state = .signingIn
    notice = nil
    do {
      let user = try await service.signIn(credential: credential)
      state = .signedIn(user)
      do {
        try await hints.saveReauthenticationHint()
      } catch {
        notice = .unavailable("Fluke couldn't save your sign-in preference.")
      }
    } catch {
      state = .signedOut(error: presentationError(for: error))
    }
  }

  func signOut() async {
    guard let generation = beginAccountMutation() else { return }
    defer { finishAccountMutation(generation) }
    let knownUser = signedInUser
    notice = nil
    do {
      try await service.signOut()
    } catch {
      guard isCurrentAccountMutation(generation) else { return }
      if let knownUser { state = .signedIn(knownUser) }
      notice = presentationError(for: error)
      return
    }
    guard isCurrentAccountMutation(generation) else { return }
    state = .signedOut(error: nil)
    do {
      try await hints.saveReauthenticationHint()
    } catch {
      guard isCurrentAccountMutation(generation) else { return }
      notice = .unavailable("Fluke couldn't save your sign-in preference.")
    }
  }

  func deleteAccount(credential: AppleCredential) async {
    guard let knownUser = signedInUser else { return }
    guard credential.isStructurallyValid else {
      notice = .invalidAppleCredential
      return
    }
    guard let generation = beginAccountMutation() else { return }
    defer { finishAccountMutation(generation) }
    notice = nil
    do {
      try await service.deleteAccount(credential: credential)
    } catch {
      guard isCurrentAccountMutation(generation) else { return }
      state = .signedIn(knownUser)
      notice = deletionPresentationError(for: error)
      return
    }
    var cleanupError: AuthPresentationError?
    do {
      try await accountAssociations.clearAccountAssociation()
    } catch {
      cleanupError = .unavailable(
        "Your account was deleted, but queued sightings still need local cleanup."
      )
    }
    do {
      try await hints.clear()
    } catch {
      cleanupError =
        cleanupError
        ?? .unavailable(
          "Your account was deleted, but local cleanup needs another attempt."
        )
    }
    guard isCurrentAccountMutation(generation) else { return }
    state = .signedOut(error: cleanupError)
  }

  func expire() {
    invalidateAccountMutation()
    state = .signedOut(error: nil)
    notice = nil
  }

  func expireWithInvalidCredential() {
    invalidateAccountMutation()
    state = .signedOut(error: .invalidAppleCredential)
    notice = nil
  }

  func reportInvalidCredential() {
    guard signedInUser != nil else { return }
    notice = .invalidAppleCredential
  }

  private var signedInUser: AuthenticatedUser? {
    guard case .signedIn(let user) = state else { return nil }
    return user
  }

  var isAuthenticated: Bool { signedInUser != nil }
  var authenticatedEmail: String? { signedInUser?.email }

  private func beginAccountMutation() -> UInt64? {
    guard !isAccountMutationInFlight else { return nil }
    accountMutationGeneration &+= 1
    activeAccountMutationGeneration = accountMutationGeneration
    isAccountMutationInFlight = true
    return accountMutationGeneration
  }

  private func isCurrentAccountMutation(_ generation: UInt64) -> Bool {
    isAccountMutationInFlight
      && activeAccountMutationGeneration == generation
      && accountMutationGeneration == generation
  }

  private func finishAccountMutation(_ generation: UInt64) {
    guard isCurrentAccountMutation(generation) else { return }
    activeAccountMutationGeneration = nil
    isAccountMutationInFlight = false
  }

  private func invalidateAccountMutation() {
    accountMutationGeneration &+= 1
    activeAccountMutationGeneration = nil
    isAccountMutationInFlight = false
  }

  private func presentationError(for error: Error) -> AuthPresentationError {
    if error as? AuthServiceError == .invalidAppleCredential {
      return .invalidAppleCredential
    }
    if let apiError = error as? APIError {
      let message = apiError.errorDescription ?? "Fluke couldn't reach the service."
      return apiError.retryable ? .retryable(message) : .unavailable(message)
    }
    return .unavailable("Fluke couldn't complete the account request.")
  }

  private func deletionPresentationError(for error: Error) -> AuthPresentationError {
    switch presentationError(for: error) {
    case .retryable(let message):
      return .retryable(
        "Your account was not deleted. \(message) Confirm with Apple again to retry."
      )
    case .unavailable(let message):
      return .unavailable("Your account was not deleted. \(message)")
    case .invalidAppleCredential:
      return .invalidAppleCredential
    }
  }
}
