import Foundation
import FlukeKit
import FlukeReleaseB
import Testing

@testable import Fluke

@MainActor
struct AppStoreScreenshotFixtureTests {
  @Test("The fixture launch seam requires both XCTest and its explicit argument")
  func fixtureLaunchRequiresXCTestAndArgument() {
    let argument = AppStoreScreenshotFixtureMode.launchArgument

    #expect(!AppStoreScreenshotFixtureMode.isEnabled(arguments: [argument], environment: [:]))
    #expect(!AppStoreScreenshotFixtureMode.isEnabled(
      arguments: [],
      environment: ["XCTestConfigurationFilePath": "/tmp/fixture.xctestconfiguration"]
    ))
    #expect(AppStoreScreenshotFixtureMode.isEnabled(
      arguments: [argument],
      environment: ["FLUKE_XCTEST_FIXTURES": "1"]
    ))
  }

  @Test("The screenshot transport exposes exact launch capabilities")
  func fixtureCapabilities() async throws {
    let environment = try AppStoreScreenshotFixtures.makeEnvironment()
    let capabilities = try await environment.fetchCapabilities()

    #expect(capabilities.accounts)
    #expect(!capabilities.identification)
    #expect(capabilities.submissions)
    #expect(environment.submissionObservedAt() == Date(timeIntervalSince1970: 1_784_224_800))
  }

  @Test("The screenshot transport serves deterministic browse data without live I/O")
  func fixtureBrowseData() async throws {
    let environment = try AppStoreScreenshotFixtures.makeEnvironment()
    let sightings = try await environment.sightingsRepository.loadApproved()
    let whales = try await environment.whalesRepository.loadCatalog()
    let feed = try await environment.sightingFeedRepository.load()

    guard case .fresh(let sightingValues, _) = sightings,
      case .fresh(let whaleValues, _) = whales
    else {
      Issue.record("Expected fresh screenshot browse fixtures")
      return
    }
    #expect(sightingValues.count == 3)
    #expect(whaleValues.count == 3)
    #expect(sightingValues.first?.locationName == "Salish Sea")
    #expect(whaleValues.first?.catalogId == "J35")
    #expect(feed.items.count == 3)
    #expect(feed.syncCursor == "fixture-r3")
  }
}
