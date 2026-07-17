import FlukeKit
import Foundation
import Testing

@testable import Fluke

@MainActor
struct LaunchCapabilityTests {
  @Test("Accounts and submissions enable independently while identify stays honest")
  func releaseCapabilities() async throws {
    let decoded = try JSONDecoder().decode(
      Capabilities.self,
      from: Data(#"{"accounts":true,"identification":false,"submissions":true}"#.utf8)
    )

    let state = await LaunchCapabilityState.load { decoded }

    #expect(
      state == .available(
        LaunchCapabilities(
          accounts: true,
          identification: false,
          submissions: true
        )
      )
    )
  }

  @Test("Malformed or unavailable capability state fails closed")
  func unavailableCapabilities() async {
    let state = await LaunchCapabilityState.load {
      throw URLError(.cannotConnectToHost)
    }

    #expect(state == .unavailable)
  }

  @Test("The app environment accepts an isolated capability source")
  func environmentUsesInjectedCapabilitySource() async throws {
    let decoded = try JSONDecoder().decode(
      Capabilities.self,
      from: Data(#"{"accounts":false,"identification":true,"submissions":false}"#.utf8)
    )
    let environment = try AppEnvironment.make(
      apiBaseURLString: "https://api.fluke.test",
      configuration: .release,
      capabilitiesFetch: { decoded }
    )

    let state = await LaunchCapabilityState.load(
      using: environment.fetchCapabilities
    )

    #expect(
      state == .available(
        LaunchCapabilities(
          accounts: false,
          identification: true,
          submissions: false
        )
      )
    )
  }
}
