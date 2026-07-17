import FlukeFeatures
import FlukeKit
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

  var body: some View {
    TabView(selection: $selectedTab) {
      NavigationStack {
        SightingsPlaceholder()
      }
      .tabItem { tabLabel(for: .sightings) }
      .tag(RootTab.sightings)

      NavigationStack {
        WhalesPlaceholder()
      }
      .tabItem { tabLabel(for: .whales) }
      .tag(RootTab.whales)

      NavigationStack {
        LearnPlaceholder()
      }
      .tabItem { tabLabel(for: .learn) }
      .tag(RootTab.learn)

      AtlasView(
        historicalRepo: environment.historicalSightingsRepository,
        predictionRepo: environment.predictionRepository,
        whalesRepo: environment.whalesRepository,
        catalog: []
      )
      .tabItem { tabLabel(for: .atlas) }
      .tag(RootTab.atlas)
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

private struct ReleaseACapabilitiesKey: EnvironmentKey {
  static let defaultValue = ReleaseACapabilityState.disabled
}

extension EnvironmentValues {
  fileprivate var releaseACapabilities: ReleaseACapabilityState {
    get { self[ReleaseACapabilitiesKey.self] }
    set { self[ReleaseACapabilitiesKey.self] = newValue }
  }
}
