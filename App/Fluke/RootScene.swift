import FlukeFeatures
import FlukeKit
import FlukeUI
import SwiftUI

enum RootTab: CaseIterable, Hashable {
  case sightings
  case whales
  case learn
  case atlas

  var title: String {
    switch self {
    case .sightings: "Sightings"
    case .whales: "Whales"
    case .learn: "Learn"
    case .atlas: "Atlas"
    }
  }

  var systemImage: String {
    switch self {
    case .sightings: "map"
    case .whales: "water.waves"
    case .learn: "book"
    case .atlas: "globe.americas"
    }
  }
}

struct RootScene: View {
  let environment: AppEnvironment

  @State private var capabilities = ReleaseACapabilityState.disabled
  @State private var selectedTab = RootTab.sightings
  @State private var requestedTraceWhaleID: String?
  @State private var atlasRouteRevision = 0

  var body: some View {
    ZStack {
      Color.fog.ignoresSafeArea()

      TabView(selection: $selectedTab) {
        NavigationStack {
          SightingsView(repository: environment.sightingsRepository)
        }
        .flukeNavigationBackground()
        .tabItem { tabLabel(for: .sightings) }
        .tag(RootTab.sightings)

        NavigationStack {
          WhalesView(repository: environment.whalesRepository) { whale in
            requestedTraceWhaleID = whale.id
            atlasRouteRevision += 1
            selectedTab = .atlas
          }
        }
        .flukeNavigationBackground()
        .tabItem { tabLabel(for: .whales) }
        .tag(RootTab.whales)

        NavigationStack {
          LearnView()
        }
        .flukeNavigationBackground()
        .tabItem { tabLabel(for: .learn) }
        .tag(RootTab.learn)

        AtlasView(
          historicalRepository: environment.historicalSightingsRepository,
          predictionRepository: environment.predictionRepository,
          whalesRepository: environment.whalesRepository,
          requestedTraceWhaleID: requestedTraceWhaleID
        )
        .id(atlasRouteRevision)
        .tabItem { tabLabel(for: .atlas) }
        .tag(RootTab.atlas)
      }
    }
    .task {
      capabilities = await ReleaseACapabilityState.load(
        using: environment.fetchCapabilities
      )
    }
    .environment(\.releaseACapabilities, capabilities)
  }

  private func tabLabel(for tab: RootTab) -> some View {
    Label(tab.title, systemImage: tab.systemImage)
  }
}

private extension View {
  func flukeNavigationBackground() -> some View {
    toolbarBackground(Color.fog, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
  }
}

private struct ReleaseACapabilitiesKey: EnvironmentKey {
  static let defaultValue = ReleaseACapabilityState.disabled
}

extension EnvironmentValues {
  fileprivate var releaseACapabilities: ReleaseACapabilityState {
    get { self[ReleaseACapabilitiesKey.self] }
    set { self[ReleaseACapabilitiesKey.self] = newValue }
  }
}
