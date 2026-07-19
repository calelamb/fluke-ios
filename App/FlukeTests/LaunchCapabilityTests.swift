import FlukeFeatures
import FlukeKit
import FlukeML
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
            identificationMode: .disabled,
            submissions: true
          )
        )
    )
  }

  @Test("Malformed or unavailable capability state fails closed")
  func unavailableCapabilities() async {
    let state = await LaunchCapabilityState.load(
      using: { throw URLError(.cannotConnectToHost) },
      retryDelaysNanoseconds: []
    )

    #expect(state == .unavailable)
  }

  @Test("A cold API wake retries capabilities before failing closed")
  func retriesColdWake() async throws {
    let decoded = try JSONDecoder().decode(
      Capabilities.self,
      from: Data(#"{"accounts":true,"identification":false,"submissions":true}"#.utf8)
    )
    let recorder = CapabilityAttemptRecorder(
      results: [.failure(URLError(.timedOut)), .failure(URLError(.timedOut)), .success(decoded)]
    )

    let state = await LaunchCapabilityState.load(
      using: { try await recorder.fetch() },
      retryDelaysNanoseconds: [1, 2],
      sleep: { await recorder.recordSleep($0) }
    )

    #expect(
      state == .available(
        .init(
          accounts: true,
          identification: false,
          identificationMode: .disabled,
          submissions: true
        )
      )
    )
    #expect(await recorder.fetchCount == 3)
    #expect(await recorder.sleeps == [1, 2])
  }

  @Test("Capability retry exhaustion remains fail closed")
  func retryExhaustion() async {
    let recorder = CapabilityAttemptRecorder(results: [
      .failure(URLError(.timedOut)), .failure(URLError(.cannotConnectToHost)),
    ])

    let state = await LaunchCapabilityState.load(
      using: { try await recorder.fetch() },
      retryDelaysNanoseconds: [1],
      sleep: { await recorder.recordSleep($0) }
    )

    #expect(state == .unavailable)
    #expect(await recorder.fetchCount == 2)
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
            identificationMode: .server,
            submissions: false
          )
        )
    )
  }

  @Test("cached on-device mode survives an offline launch only with a loaded identifier")
  func cachedOnDeviceResolution() {
    let identifier = NeverLocalIdentifier()

    let available = IdentificationComposition.resolve(
      capabilities: .unavailable,
      cachedMode: .onDevice,
      localIdentifier: .available(identifier)
    )
    let missing = IdentificationComposition.resolve(
      capabilities: .unavailable,
      cachedMode: .onDevice,
      localIdentifier: .unavailable
    )

    guard case .onDevice = available else {
      Issue.record("Expected cached on-device identification")
      return
    }
    #expect(missing.matchingInactiveReason == .artifactsUnavailable)
  }

  @Test("server mode is explicitly unsupported in the shipping composition")
  func serverModeUnsupported() {
    let capability = IdentificationComposition.resolve(
      capabilities: .available(
        .init(
          accounts: true,
          identification: true,
          identificationMode: .server,
          submissions: true
        )
      ),
      cachedMode: .onDevice,
      localIdentifier: .available(NeverLocalIdentifier())
    )

    #expect(capability.unavailableReason == .serverUnsupported)
  }
}

private actor CapabilityAttemptRecorder {
  private var results: [Result<Capabilities, Error>]
  private(set) var fetchCount = 0
  private(set) var sleeps: [UInt64] = []

  init(results: [Result<Capabilities, Error>]) { self.results = results }

  func fetch() throws -> Capabilities {
    fetchCount += 1
    guard !results.isEmpty else { throw URLError(.cannotConnectToHost) }
    return try results.removeFirst().get()
  }

  func recordSleep(_ nanoseconds: UInt64) { sleeps.append(nanoseconds) }
}

private struct NeverLocalIdentifier: LocalIdentifying {
  func identify(frame: CameraFrame) async throws -> LocalIdentificationState {
    throw CancellationError()
  }
}
