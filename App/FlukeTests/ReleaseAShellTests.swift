import FlukeKit
import Foundation
import Testing

@testable import Fluke

@MainActor
struct ReleaseAShellTests {
  @Test("Release A exposes exactly four browse tabs")
  func releaseATabs() {
    #expect(
      RootTab.allCases.map(\.title) == [
        "Sightings",
        "Whales",
        "Learn",
        "Atlas",
      ])
  }

  @Test("Capabilities remain disabled when loading fails")
  func capabilityFailureFailsClosed() async {
    let state = await ReleaseACapabilityState.load {
      throw CapabilityFixtureError.unavailable
    }

    #expect(state == .disabled)
  }

  @Test("Unexpected enabled capabilities fail closed")
  func enabledCapabilitiesFailClosed() async throws {
    let capabilities = try decodeCapabilities(
      #"{"accounts":false,"identification":true,"submissions":false}"#
    )

    let state = await ReleaseACapabilityState.load { capabilities }

    #expect(state == .disabled)
  }

  @Test("Disabled server capabilities are applied")
  func disabledCapabilitiesAreApplied() async throws {
    let capabilities = try decodeCapabilities(
      #"{"accounts":false,"identification":false,"submissions":false}"#
    )

    let state = await ReleaseACapabilityState.load { capabilities }

    #expect(state == .disabled)
  }

  @Test("The app environment accepts an isolated capability source")
  func environmentUsesInjectedCapabilitySource() async throws {
    let capabilities = try decodeCapabilities(
      #"{"accounts":false,"identification":false,"submissions":false}"#
    )
    let environment = try AppEnvironment.make(
      apiBaseURLString: "https://api.fluke.test",
      configuration: .release,
      capabilitiesFetch: { capabilities }
    )

    let state = await ReleaseACapabilityState.load(
      using: environment.fetchCapabilities
    )

    #expect(state == .disabled)
  }

  private func decodeCapabilities(_ json: String) throws -> Capabilities {
    try JSONDecoder().decode(Capabilities.self, from: Data(json.utf8))
  }
}

private enum CapabilityFixtureError: Error {
  case unavailable
}
