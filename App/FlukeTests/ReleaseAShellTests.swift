import FlukeKit
import FlukeUI
import Foundation
import SwiftUI
import Testing
import UIKit

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

  @Test("App initialization registers the branded font before rendering")
  func appRegistersFraunces() {
    _ = FlukeApp()

    #expect(UIFont(name: "Fraunces", size: 24) != nil)
  }

  @Test("The fixed PNW palette always launches with legible light system chrome")
  func launchAppearance() {
    #expect(FlukeApp.preferredColorScheme == .light)
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
