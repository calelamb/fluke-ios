import FlukeKit
import FlukeReleaseB
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
      state
        == .available(
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
      state
        == .available(
          LaunchCapabilities(
            accounts: false,
            identification: true,
            submissions: false
          )
        )
    )
  }

  @Test("Disabled identification never constructs its service")
  func disabledIdentificationCompositionIsLazy() {
    let recorder = IdentifyFactoryRecorder()

    let service = IdentifyComposition.resolve(
      enabled: false,
      factory: { recorder.makeService() }
    )

    #expect(service == nil)
    #expect(recorder.constructionCount == 0)
  }
}

@MainActor
private final class IdentifyFactoryRecorder {
  private(set) var constructionCount = 0

  func makeService() -> any IdentifyServiceProtocol {
    constructionCount += 1
    return NeverIdentifyService()
  }
}

private struct NeverIdentifyService: IdentifyServiceProtocol {
  func identify(photo: IdentifyPhoto) async throws -> IdentifyResponse {
    throw CancellationError()
  }
}
