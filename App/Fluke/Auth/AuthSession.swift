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
  func clearAccountAssociation() async
}

nonisolated struct EmptyAccountAssociationStore: AccountAssociationClearing {
  func clearAccountAssociation() async {}
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

  private let service: any AuthServiceProtocol
  private let hints: any SessionHintStore
  private let accountAssociations: any AccountAssociationClearing

  init(
    service: any AuthServiceProtocol,
    hints: any SessionHintStore,
    accountAssociations: any AccountAssociationClearing = EmptyAccountAssociationStore()
  ) {
    self.service = service
    self.hints = hints
    self.accountAssociations = accountAssociations
  }

  func restore() async {
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
    guard let token = String(data: credential.identityToken, encoding: .utf8),
      !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
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
    let knownUser = signedInUser
    notice = nil
    do {
      try await service.signOut()
    } catch {
      if let knownUser { state = .signedIn(knownUser) }
      notice = presentationError(for: error)
      return
    }
    state = .signedOut(error: nil)
    do {
      try await hints.saveReauthenticationHint()
    } catch {
      notice = .unavailable("Fluke couldn't save your sign-in preference.")
    }
  }

  func deleteAccount() async {
    guard let knownUser = signedInUser else { return }
    notice = nil
    do {
      try await service.deleteAccount()
    } catch {
      state = .signedIn(knownUser)
      notice = presentationError(for: error)
      return
    }
    await accountAssociations.clearAccountAssociation()
    state = .signedOut(error: nil)
    do {
      try await hints.clear()
    } catch {
      notice = .unavailable("Your account was deleted, but local cleanup needs another attempt.")
    }
  }

  func expire() {
    state = .signedOut(error: nil)
    notice = nil
  }

  private var signedInUser: AuthenticatedUser? {
    guard case .signedIn(let user) = state else { return nil }
    return user
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
}
