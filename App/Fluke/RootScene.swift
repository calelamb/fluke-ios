import AuthenticationServices
import FlukeFeatures
import FlukeKit
import FlukeReleaseB
import FlukeUI
import Foundation
import SwiftUI

enum RootTab: CaseIterable, Hashable {
  case sightings
  case whales
  case identify
  case learn
  case you

  var title: String {
    switch self {
    case .sightings: "Sightings"
    case .whales: "Whales"
    case .identify: "Identify"
    case .learn: "Learn"
    case .you: "You"
    }
  }

  var systemImage: String {
    switch self {
    case .sightings: "map"
    case .whales: "water.waves"
    case .identify: "camera.viewfinder"
    case .learn: "book"
    case .you: "person.crop.circle"
    }
  }
}

struct RootScene: View {
  let environment: AppEnvironment
  private let submissionQueue: DeferredSubmissionQueueBridge

  @State private var authSession: AuthSession
  @State private var capabilities = LaunchCapabilityState.loading
  @State private var selectedTab = RootTab.sightings
  @State private var requestedTraceWhaleID: String?
  @State private var atlasRouteRevision = 0
  @State private var isAtlasPresented = false

  init(environment: AppEnvironment) {
    let submissionQueue = DeferredSubmissionQueueBridge()
    self.environment = environment
    self.submissionQueue = submissionQueue
    _authSession = State(
      initialValue: AuthSession(
        service: environment.authService,
        hints: environment.sessionHintStore,
        accountAssociations: submissionQueue
      )
    )
  }

  var body: some View {
    ZStack {
      Color.fog.ignoresSafeArea()

      TabView(selection: $selectedTab) {
        NavigationStack {
          SightingsView(repository: environment.sightingsRepository)
            .toolbar {
              ToolbarItem(placement: .topBarTrailing) {
                Button {
                  presentAtlas()
                } label: {
                  Label("Open Atlas", systemImage: "globe.americas")
                }
              }
            }
        }
        .flukeNavigationBackground()
        .tabItem { tabLabel(for: .sightings) }
        .tag(RootTab.sightings)

        NavigationStack {
          WhalesView(repository: environment.whalesRepository) { whale in
            presentAtlas(for: whale.id)
          }
        }
        .flukeNavigationBackground()
        .tabItem { tabLabel(for: .whales) }
        .tag(RootTab.whales)

        NavigationStack {
          IdentifyView(capabilities: capabilities)
        }
        .flukeNavigationBackground()
        .tabItem { tabLabel(for: .identify) }
        .tag(RootTab.identify)

        NavigationStack {
          LearnView()
        }
        .flukeNavigationBackground()
        .tabItem { tabLabel(for: .learn) }
        .tag(RootTab.learn)

        NavigationStack {
          FlukeFeatures.YouView(
            availability: accountAvailability,
            authState: youAuthState,
            repository: environment.logbookRepository,
            queue: submissionQueue,
            configureAppleRequest: AppleAuthorizationAdapter.configure,
            completeAppleAuthorization: completeAppleAuthorization,
            signOut: { Task { await authSession.signOut() } },
            deleteAccount: { Task { await authSession.deleteAccount() } },
            sessionExpired: { authSession.expire() }
          )
        }
        .flukeNavigationBackground()
        .tabItem { tabLabel(for: .you) }
        .tag(RootTab.you)
      }
    }
    .flukeSystemContrast()
    .task {
      capabilities = await LaunchCapabilityState.load(
        using: environment.fetchCapabilities
      )
      if accountAvailability == .enabled {
        await authSession.restore()
      } else {
        authSession.expire()
      }
    }
    .environment(\.launchCapabilities, capabilities)
    .environment(\.openAtlas) { whaleID in
      presentAtlas(for: whaleID)
    }
    .environment(\.openSubmit) {}
    .fullScreenCover(isPresented: $isAtlasPresented) {
      AtlasView(
        historicalRepository: environment.historicalSightingsRepository,
        predictionRepository: environment.predictionRepository,
        whalesRepository: environment.whalesRepository,
        requestedTraceWhaleID: requestedTraceWhaleID
      )
      .id(atlasRouteRevision)
      .overlay(alignment: .topTrailing) {
        Button("Close", systemImage: "xmark") {
          isAtlasPresented = false
        }
        .labelStyle(.iconOnly)
        .accessibilityLabel("Close Atlas")
        .padding()
      }
    }
  }

  private func tabLabel(for tab: RootTab) -> some View {
    Label(tab.title, systemImage: tab.systemImage)
  }

  private func presentAtlas(for whaleID: String? = nil) {
    requestedTraceWhaleID = whaleID
    atlasRouteRevision += 1
    isAtlasPresented = true
  }

  private var accountAvailability: YouAccountAvailability {
    switch capabilities {
    case .loading: .loading
    case .available(let value): value.accounts ? .enabled : .disabled
    case .unavailable: .disabled
    }
  }

  private var youAuthState: YouAuthState {
    let notice = authSession.notice?.message
    switch authSession.state {
    case .restoring: return YouAuthState.restoring
    case .signingIn: return YouAuthState.signingIn
    case .signedOut(let error):
      return YouAuthState.signedOut(message: error?.message ?? notice)
    case .signedIn(let user):
      return YouAuthState.signedIn(user: user, notice: notice)
    }
  }

  private func completeAppleAuthorization(_ result: Result<ASAuthorization, Error>) {
    switch AppleAuthorizationAdapter.credential(from: result) {
    case .success(let credential):
      Task { await authSession.signIn(credential: credential) }
    case .failure:
      Task {
        await authSession.signIn(
          credential: AppleCredential(identityToken: Data(), fullName: nil)
        )
      }
    }
  }
}

extension View {
  fileprivate func flukeNavigationBackground() -> some View {
    toolbarBackground(Color.fog, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
  }
}

private struct LaunchCapabilitiesKey: EnvironmentKey {
  static let defaultValue = LaunchCapabilityState.loading
}

private struct OpenAtlasKey: EnvironmentKey {
  static let defaultValue: (String?) -> Void = { _ in }
}

private struct OpenSubmitKey: EnvironmentKey {
  static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
  var launchCapabilities: LaunchCapabilityState {
    get { self[LaunchCapabilitiesKey.self] }
    set { self[LaunchCapabilitiesKey.self] = newValue }
  }

  var openAtlas: (String?) -> Void {
    get { self[OpenAtlasKey.self] }
    set { self[OpenAtlasKey.self] = newValue }
  }

  var openSubmit: () -> Void {
    get { self[OpenSubmitKey.self] }
    set { self[OpenSubmitKey.self] = newValue }
  }
}

private struct IdentifyView: View {
  let capabilities: LaunchCapabilityState

  var body: some View {
    ContentUnavailableView(
      "Photo identification is in training",
      systemImage: "camera.viewfinder",
      description: Text(description)
    )
    .navigationTitle("Identify")
  }

  private var description: String {
    "Photo identification is still in training. We are building a rights-cleared reference catalog before we compare your photo. Browse the whale catalog or submit a sighting in the meantime."
  }
}

extension AuthPresentationError {
  fileprivate var message: String {
    switch self {
    case .invalidAppleCredential:
      "Sign in with Apple did not return a valid credential. Please try again."
    case .retryable(let message), .unavailable(let message):
      message
    }
  }
}
