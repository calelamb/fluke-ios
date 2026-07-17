import FlukeFeatures
import FlukeKit
import FlukeUI
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

  @State private var capabilities = LaunchCapabilityState.loading
  @State private var selectedTab = RootTab.sightings
  @State private var requestedTraceWhaleID: String?
  @State private var atlasRouteRevision = 0
  @State private var isAtlasPresented = false

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
          YouView(capabilities: capabilities)
        }
        .flukeNavigationBackground()
        .tabItem { tabLabel(for: .you) }
        .tag(RootTab.you)
      }
    }
    .task {
      capabilities = await LaunchCapabilityState.load(
        using: environment.fetchCapabilities
      )
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
}

private extension View {
  func flukeNavigationBackground() -> some View {
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

private struct YouView: View {
  let capabilities: LaunchCapabilityState

  var body: some View {
    ContentUnavailableView(
      "Your Fluke activity",
      systemImage: "person.crop.circle",
      description: Text("Account and sighting history will appear here when available.")
    )
    .navigationTitle("You")
  }
}
