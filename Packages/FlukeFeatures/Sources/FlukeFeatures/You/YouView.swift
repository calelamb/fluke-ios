import AuthenticationServices
import FlukeReleaseB
import FlukeUI
import SwiftUI

public enum YouAccountAvailability: Equatable, Sendable {
  case loading
  case enabled
  case disabled
}

public enum YouAuthState: Equatable, Sendable {
  case restoring
  case signedOut(message: String?)
  case signingIn
  case signedIn(user: AuthenticatedUser, notice: String?)
}

public struct YouView: View {
  private let availability: YouAccountAvailability
  private let authState: YouAuthState
  private let repository: any LogbookRepositoryProtocol
  private let queue: any QueuedLogbookProviding
  private let configureAppleRequest: (ASAuthorizationAppleIDRequest) -> Void
  private let completeAppleAuthorization: (Result<ASAuthorization, Error>) -> Void
  private let signOut: () -> Void
  private let deleteAccount: () -> Void
  private let sessionExpired: () -> Void

  @State private var confirmsDeletion = false

  public init(
    availability: YouAccountAvailability,
    authState: YouAuthState,
    repository: any LogbookRepositoryProtocol,
    queue: any QueuedLogbookProviding = EmptyLogbookQueue(),
    configureAppleRequest: @escaping (ASAuthorizationAppleIDRequest) -> Void,
    completeAppleAuthorization: @escaping (Result<ASAuthorization, Error>) -> Void,
    signOut: @escaping () -> Void,
    deleteAccount: @escaping () -> Void,
    sessionExpired: @escaping () -> Void
  ) {
    self.availability = availability
    self.authState = authState
    self.repository = repository
    self.queue = queue
    self.configureAppleRequest = configureAppleRequest
    self.completeAppleAuthorization = completeAppleAuthorization
    self.signOut = signOut
    self.deleteAccount = deleteAccount
    self.sessionExpired = sessionExpired
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        accountContent
        resourceLinks
      }
      .padding(20)
      .frame(maxWidth: 680)
      .frame(maxWidth: .infinity)
    }
    .background(Color.fog)
    .navigationTitle("You")
    .alert("Delete your Fluke account?", isPresented: $confirmsDeletion) {
      Button("Cancel", role: .cancel) {}
      Button("Delete account", role: .destructive, action: deleteAccount)
    } message: {
      Text(
        "Your linked personal details will be removed. Approved public wildlife observations may remain in anonymized form. This cannot be undone."
      )
    }
  }

  @ViewBuilder
  private var accountContent: some View {
    switch availability {
    case .loading:
      ProgressView("Checking account availability")
        .frame(maxWidth: .infinity, minHeight: 180)
    case .disabled:
      ContentUnavailableView(
        "Accounts are temporarily unavailable",
        systemImage: "person.crop.circle.badge.exclamationmark",
        description: Text("You can keep browsing and submitting sightings without an account.")
      )
    case .enabled:
      enabledAccountContent
    }
  }

  @ViewBuilder
  private var enabledAccountContent: some View {
    switch authState {
    case .restoring:
      ProgressView("Restoring your account")
        .frame(maxWidth: .infinity, minHeight: 180)
    case .signingIn:
      ProgressView("Signing in")
        .frame(maxWidth: .infinity, minHeight: 180)
    case .signedOut(let message):
      signedOutContent(message: message)
    case .signedIn(let user, let notice):
      signedInContent(user: user, notice: notice)
    }
  }

  private func signedOutContent(message: String?) -> some View {
    VStack(spacing: 16) {
      DorsalFinShape()
        .fill(Color.tide)
        .frame(width: 72, height: 72)
        .accessibilityHidden(true)
      Text("Keep your sightings together")
        .font(.flukeDisplayMedium)
        .foregroundStyle(Color.abyss)
        .multilineTextAlignment(.center)
      Text("Browsing and submitting do not require an account.")
        .font(.flukeBody)
        .foregroundStyle(Color.deep)
        .multilineTextAlignment(.center)
      if let message {
        Text(message)
          .font(.flukeBody)
          .foregroundStyle(Color.abyss)
          .padding(12)
          .background(Color.ember.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
      }
      SignInWithAppleButton(
        .signIn,
        onRequest: configureAppleRequest,
        onCompletion: completeAppleAuthorization
      )
      .signInWithAppleButtonStyle(.black)
      .frame(height: 50)
      .frame(maxWidth: 360)
      .accessibilityHint("Signs in without sharing an Apple password with Fluke")
    }
    .padding(24)
    .frame(maxWidth: .infinity)
    .background(Color.bone, in: RoundedRectangle(cornerRadius: 18))
  }

  private func signedInContent(user: AuthenticatedUser, notice: String?) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Hello, \(greetingName(for: user))")
        .font(.flukeDisplayMedium)
        .foregroundStyle(Color.abyss)
      if let notice {
        Text(notice)
          .font(.flukeBody)
          .foregroundStyle(Color.abyss)
          .padding(12)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color.ember.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
      }
      Text("Logbook")
        .font(.flukeDisplayMedium)
        .foregroundStyle(Color.abyss)
      LogbookView(
        repository: repository,
        queue: queue,
        onSessionExpired: sessionExpired
      )
      Divider()
      Button("Sign out", action: signOut)
        .buttonStyle(.bordered)
        .tint(Color.tide)
      Button("Delete account", role: .destructive) {
        confirmsDeletion = true
      }
    }
  }

  private var resourceLinks: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("About Fluke")
        .font(.flukeDisplaySmall)
        .foregroundStyle(Color.abyss)
      Text("An independent guide to sourced Pacific Northwest orca observations.")
        .font(.flukeBody)
        .foregroundStyle(Color.deep)
      links
    }
    .padding(18)
    .background(Color.bone, in: RoundedRectangle(cornerRadius: 14))
  }

  private var links: some View {
    HStack(spacing: 16) {
      resourceLink("About", path: "")
      resourceLink("Privacy", path: "privacy")
      resourceLink("Support", path: "support")
      resourceLink("Attribution", path: "sources")
    }
    .font(.flukeBody)
  }

  @ViewBuilder
  private func resourceLink(_ title: String, path: String) -> some View {
    if let base = URL(string: "https://fluke-pnw.vercel.app"),
      let url = path.isEmpty ? base : URL(string: path, relativeTo: base)
    {
      Link(title, destination: url)
    }
  }

  private func greetingName(for user: AuthenticatedUser) -> String {
    let name = user.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let name, !name.isEmpty { return name }
    return user.email
  }
}
