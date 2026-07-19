import FlukeKit
import FlukeML
import FlukeReleaseB
import Foundation
import SwiftUI
import Testing
import UIKit

@testable import Fluke

@MainActor
@Suite("Identification launch integration")
struct IdentificationLaunchIntegrationTests {
  @Test("capabilities and account restore resolve while local artifacts are suspended")
  func remoteLaunchDoesNotAwaitLocalArtifacts() async throws {
    let localLoad = SuspendedLaunchIdentifierLoad()
    let capabilities = LaunchCapabilitiesRecorder()
    let auth = LaunchAuthRecorder()
    let environment = try AppEnvironment.make(
      apiBaseURLString: "https://api.fluke.test",
      configuration: .release,
      capabilitiesFetch: { try await capabilities.fetch() },
      authService: auth,
      localIdentifierLoad: { try await localLoad.load() }
    )
    let host = UIHostingController(rootView: RootScene(environment: environment))
    let window = UIWindow(frame: UIScreen.main.bounds)
    window.rootViewController = host
    window.makeKeyAndVisible()
    await localLoad.waitUntilRequested()
    for _ in 0..<100 where await capabilities.fetchCount == 0 { await Task.yield() }
    for _ in 0..<100 where await auth.currentUserCount == 0 { await Task.yield() }

    #expect(await capabilities.fetchCount == 1)
    #expect(await capabilities.last?.submissions == true)
    #expect(await auth.currentUserCount == 1)

    await localLoad.resume()
    window.isHidden = true
  }
}

private actor SuspendedLaunchIdentifierLoad {
  private var continuation: CheckedContinuation<Void, Never>?
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private var requested = false

  func load() async throws -> any LocalIdentifying {
    requested = true
    let ready = waiters
    waiters = []
    for waiter in ready { waiter.resume() }
    await withCheckedContinuation { continuation = $0 }
    return LaunchNeverIdentifier()
  }

  func waitUntilRequested() async {
    guard !requested else { return }
    await withCheckedContinuation { waiters.append($0) }
  }

  func resume() {
    continuation?.resume()
    continuation = nil
  }
}

private actor LaunchCapabilitiesRecorder {
  private(set) var fetchCount = 0
  private(set) var last: LaunchCapabilities?

  func fetch() throws -> Capabilities {
    fetchCount += 1
    let data = Data(
      #"{"accounts":true,"identification":true,"identificationMode":"on-device","submissions":true}"#
        .utf8
    )
    let decoded = try JSONDecoder().decode(Capabilities.self, from: data)
    last = LaunchCapabilities(
      accounts: decoded.accounts,
      identification: decoded.identification,
      identificationMode: decoded.identificationMode,
      submissions: decoded.submissions
    )
    return decoded
  }
}

private actor LaunchAuthRecorder: AuthServiceProtocol {
  private(set) var currentUserCount = 0

  func signIn(credential _: AppleCredential) async throws -> AuthenticatedUser {
    currentUser()
  }

  func currentUser() -> AuthenticatedUser {
    currentUserCount += 1
    return AuthenticatedUser(
      id: "observer-1",
      email: "observer@example.com",
      displayName: "Observer",
      role: "OBSERVER"
    )
  }

  func signOut() {}
  func deleteAccount(credential _: AppleCredential) {}
}

private struct LaunchNeverIdentifier: LocalIdentifying {
  func identify(frame _: CameraFrame) async throws -> LocalIdentificationState {
    throw CancellationError()
  }
}
