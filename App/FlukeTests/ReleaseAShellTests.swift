import FlukeKit
import Foundation
import Testing

@testable import Fluke

@MainActor
struct ReleaseAShellTests {
  @Test("The launch app exposes the five approved destinations")
  func launchTabs() {
    #expect(
      RootTab.allCases.map(\.title) == [
        "Sightings",
        "Whales",
        "Identify",
        "Learn",
        "You",
      ])
  }

  @Test("The app environment accepts one isolated browse cache")
  func environmentUsesInjectedBrowseCache() throws {
    let cache = MemoryBrowseCacheStore()
    let environment = try AppEnvironment.make(
      apiBaseURLString: "https://api.fluke.test",
      configuration: .release,
      cacheStore: cache
    )

    #expect(environment.browseCacheStore is MemoryBrowseCacheStore)
    _ = environment.sightingsRepository
  }
}
