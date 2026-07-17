import AuthenticationServices
import FlukeFeatures
import FlukeKit
import FlukeReleaseB
import FlukeUI
import Foundation
import Network
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
  private let submissionReplay: SubmissionReplayActor
  private let networkMonitor = NWPathMonitor()

  @Environment(\.scenePhase) private var scenePhase

  @State private var authSession: AuthSession
  @State private var signInAuthorizationFlow: AppleAuthorizationFlow
  @State private var deletionAuthorizationFlow: AppleAuthorizationFlow
  @State private var capabilities = LaunchCapabilityState.loading
  @State private var identifyService: (any IdentifyServiceProtocol)?
  @State private var movementNavigation: MovementNavigationModel
  @State private var movementSubmitPresentation = MovementSubmitPresentationRouter()
  @State private var selectedTab = RootTab.sightings
  @State private var requestedTraceWhaleID: String?
  @State private var atlasRouteRevision = 0
  @State private var isAtlasPresented = false

  init(environment: AppEnvironment) {
    let submissionQueue = DeferredSubmissionQueueBridge(queue: environment.submissionQueue)
    self.environment = environment
    self.submissionQueue = submissionQueue
    self.submissionReplay = SubmissionReplayActor(
      queue: environment.submissionQueue,
      service: environment.submissionService
    )
    _signInAuthorizationFlow = State(initialValue: AppleAuthorizationFlow())
    _deletionAuthorizationFlow = State(initialValue: AppleAuthorizationFlow())
    _authSession = State(
      initialValue: AuthSession(
        service: environment.authService,
        hints: environment.sessionHintStore,
        accountAssociations: submissionQueue
      )
    )
    _movementNavigation = State(
      initialValue: MovementNavigationModel(repository: environment.whalesRepository)
    )
  }

  var body: some View {
    ZStack {
      Color.fog.ignoresSafeArea()

      TabView(selection: $selectedTab) {
        NavigationStack {
          SightingsView(
            repository: environment.sightingsRepository,
            onOpenWhaleMovement: presentMovement
          )
          .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
              Button {
                presentSubmit()
              } label: {
                Label("Add Sighting", systemImage: "plus")
              }
            }
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
          } onOpenSubmit: {
            presentSubmit()
          }
        }
        .flukeNavigationBackground()
        .tabItem { tabLabel(for: .whales) }
        .tag(RootTab.whales)

        NavigationStack {
          identifyDestination
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
            accountMutationInFlight: authSession.isAccountMutationInFlight,
            signInAuthorizationPending: signInAuthorizationFlow.hasPendingNonce,
            deletionAuthorizationPending: deletionAuthorizationFlow.hasPendingNonce,
            repository: environment.logbookRepository,
            queue: submissionQueue,
            configureAppleRequest: signInAuthorizationFlow.configure,
            completeAppleAuthorization: completeSignInAuthorization,
            configureDeletionAuthorization: deletionAuthorizationFlow.configure,
            completeDeletionAuthorization: completeDeletionAuthorization,
            signOut: { Task { await authSession.signOut() } },
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
      await submissionReplay.flush()
      networkMonitor.pathUpdateHandler = { path in
        guard path.status == .satisfied else { return }
        Task { await submissionReplay.flush() }
      }
      networkMonitor.start(queue: DispatchQueue(label: "app.fluke.Fluke.submission-network"))
      let loadedCapabilities = await LaunchCapabilityState.load(
        using: environment.fetchCapabilities
      )
      capabilities = loadedCapabilities
      identifyService = IdentifyComposition.resolve(
        enabled: loadedCapabilities.identificationEnabled,
        factory: environment.identifyServiceFactory
      )
      if accountAvailability == .enabled {
        await authSession.restore()
      } else {
        authSession.expire()
      }
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { Task { await submissionReplay.flush() } }
    }
    .onDisappear { networkMonitor.cancel() }
    .environment(\.launchCapabilities, capabilities)
    .environment(\.openAtlas) { whaleID in
      presentAtlas(for: whaleID)
    }
    .environment(\.openSubmit) { presentSubmit() }
    .sheet(item: $movementSubmitPresentation.presentedRoute) { route in
      SubmitView(
        model: SubmitViewModel(
          service: environment.submissionService,
          queue: environment.submissionQueue,
          isSignedIn: authSession.isAuthenticated,
          signedInObserverEmail: authSession.authenticatedEmail,
          submissionsEnabled: route.submissionsEnabled
        )
      )
      .presentationDetents([.large])
    }
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
    .fullScreenCover(item: movementDestination, onDismiss: completeMovementDismissal) {
      destination in
      movementDestination(destination)
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

  private func presentMovement(catalogID: String) {
    Task { await movementNavigation.present(catalogID: catalogID) }
  }

  private func presentSubmit() {
    let movementPresented = movementNavigation.destination != nil
    movementSubmitPresentation.request(
      submissionsEnabled: submissionsAvailable,
      movementPresented: movementPresented
    )
    if movementPresented { movementNavigation.dismiss() }
  }

  private func completeMovementDismissal() {
    movementSubmitPresentation.movementDidDismiss()
  }

  private var movementDestination: Binding<MovementDestination?> {
    Binding(
      get: { movementNavigation.destination },
      set: { destination in
        if destination == nil { movementNavigation.dismiss() }
      }
    )
  }

  @ViewBuilder
  private func movementDestination(_ destination: MovementDestination) -> some View {
    switch destination {
    case .movement(let whale):
      MovementTrackView(
        repository: environment.whalesRepository,
        whale: whale,
        onSubmitSighting: presentSubmit
      )
    case .unavailable(let catalogID, let reason):
      NavigationStack {
        ContentUnavailableView(
          "Movement unavailable",
          systemImage: "water.waves",
          description: Text(reason.message(catalogID: catalogID))
        )
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Close") { movementNavigation.dismiss() }
          }
        }
      }
    }
  }

  private var accountAvailability: YouAccountAvailability {
    switch capabilities {
    case .loading: .loading
    case .available(let value): value.accounts ? .enabled : .disabled
    case .unavailable: .disabled
    }
  }

  private var submissionsAvailable: Bool {
    guard case .available(let value) = capabilities else { return false }
    return value.submissions
  }

  @ViewBuilder
  private var identifyDestination: some View {
    if let identifyService {
      FlukeFeatures.IdentifyView(
        service: identifyService,
        browseWhales: { selectedTab = .whales },
        submitSighting: { presentSubmit() }
      )
    } else {
      FlukeFeatures.IdentifyView(
        browseWhales: { selectedTab = .whales },
        submitSighting: { presentSubmit() }
      )
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

  private func completeSignInAuthorization(_ result: Result<ASAuthorization, Error>) {
    if AppleAuthorizationAdapter.isCancellation(result) {
      signInAuthorizationFlow.cancel()
      return
    }
    switch signInAuthorizationFlow.credential(from: result) {
    case .success(let credential):
      Task { await authSession.signIn(credential: credential) }
    case .failure:
      authSession.expireWithInvalidCredential()
    }
  }

  private func completeDeletionAuthorization(_ result: Result<ASAuthorization, Error>) {
    if AppleAuthorizationAdapter.isCancellation(result) {
      deletionAuthorizationFlow.cancel()
      return
    }
    switch deletionAuthorizationFlow.credential(from: result) {
    case .success(let credential):
      Task { await authSession.deleteAccount(credential: credential) }
    case .failure:
      authSession.reportInvalidCredential()
    }
  }
}

extension LaunchCapabilityState {
  fileprivate var identificationEnabled: Bool {
    guard case .available(let value) = self else { return false }
    return value.identification
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
