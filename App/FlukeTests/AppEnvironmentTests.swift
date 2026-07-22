import FlukeKit
import FlukeML
import Foundation
import Testing

@testable import Fluke

@MainActor
struct AppEnvironmentTests {
  @Test("Live submission replay uses a data-task-compatible foreground session")
  func submissionSessionIsNotBackground() {
    let configuration = AppEnvironment.submissionSessionConfiguration()
    #expect(configuration.identifier == nil)
  }

  @Test("Debug accepts an explicit localhost API URL")
  func debugAcceptsLocalhost() throws {
    let environment = try AppEnvironment.make(
      apiBaseURLString: "http://localhost:4000",
      publicReadBaseURLString: "http://localhost:5173",
      configuration: .debug
    )

    #expect(environment.apiBaseURL == URL(string: "http://localhost:4000"))
    #expect(environment.publicReadBaseURL == URL(string: "http://localhost:5173"))
  }

  @Test("Release separates public reads from authenticated mutations")
  func releaseSeparatesOrigins() throws {
    let environment = try AppEnvironment.make(
      apiBaseURLString: "https://fluke-api.onrender.com",
      publicReadBaseURLString: "https://fluke-pnw.vercel.app",
      configuration: .release
    )

    #expect(environment.apiBaseURL == URL(string: "https://fluke-api.onrender.com"))
    #expect(environment.publicReadBaseURL == URL(string: "https://fluke-pnw.vercel.app"))
  }

  @Test("Release requires a public read origin")
  func releaseRequiresPublicOrigin() {
    #expect(throws: AppConfigurationError.missingAPIBaseURL) {
      try AppEnvironment.make(
        apiBaseURLString: "https://fluke-api.onrender.com",
        publicReadBaseURLString: nil,
        configuration: .release
      )
    }
  }

  @Test("Release rejects an insecure public read origin")
  func releaseRejectsInsecurePublicOrigin() {
    #expect(throws: AppConfigurationError.insecureAPIBaseURL) {
      try AppEnvironment.make(
        apiBaseURLString: "https://fluke-api.onrender.com",
        publicReadBaseURLString: "http://fluke-pnw.vercel.app",
        configuration: .release
      )
    }
  }

  @Test(
    "Staging and Release reject normalized local API origins",
    arguments: [
      "https://LOCALHOST.",
      "https://api.localhost",
      "https://api.localhost.",
      "https://127.0.0.2",
      "https://127.255.255.254",
      "https://[::1]",
      "https://[0:0:0:0:0:0:0:1]",
      "https://[::ffff:127.0.0.1]",
      "https://[::ffff:127.255.255.254]",
      "https://[0:0:0:0:0:ffff:7f00:1]",
    ])
  func nonDebugRejectsLocalOrigins(apiBaseURLString: String) {
    for configuration in [AppBuildConfiguration.staging, .release] {
      #expect(throws: AppConfigurationError.localAPIBaseURL) {
        try AppEnvironment.make(
          apiBaseURLString: apiBaseURLString,
          configuration: configuration
        )
      }
    }
  }

  @Test(
    "Staging and Release reject missing API URLs",
    arguments: [
      AppBuildConfiguration.staging,
      AppBuildConfiguration.release,
    ])
  func nonDebugRejectsMissingURL(configuration: AppBuildConfiguration) {
    #expect(throws: AppConfigurationError.missingAPIBaseURL) {
      try AppEnvironment.make(
        apiBaseURLString: nil,
        configuration: configuration
      )
    }
  }

  @Test(
    "Staging and Release require HTTPS",
    arguments: [
      AppBuildConfiguration.staging,
      AppBuildConfiguration.release,
    ])
  func nonDebugRequiresHTTPS(configuration: AppBuildConfiguration) {
    #expect(throws: AppConfigurationError.insecureAPIBaseURL) {
      try AppEnvironment.make(
        apiBaseURLString: "http://api.fluke.test",
        configuration: configuration
      )
    }
  }

  @Test(
    "Production configuration accepts public HTTPS API URLs",
    arguments: [
      "https://api.fluke.test",
      "https://8.8.8.8",
      "https://[2001:4860:4860::8888]",
      "https://notlocalhost.example",
    ])
  func releaseAcceptsHTTPS(apiBaseURLString: String) throws {
    let environment = try AppEnvironment.make(
      apiBaseURLString: apiBaseURLString,
      configuration: .release
    )

    #expect(environment.apiBaseURL == URL(string: apiBaseURLString))
  }

  @Test("Missing production catalog disables local identification without blocking app services")
  func missingCatalogDoesNotBlockBootstrap() async throws {
    let environment = try AppEnvironment.make(
      apiBaseURLString: "https://api.fluke.test",
      configuration: .release
    )
    let bundle = try Self.bundleWithoutCatalog()
    defer { try? FileManager.default.removeItem(at: bundle.bundleURL) }

    let loader = OnDeviceIdentificationLoader { try await LocalIdentifier.load(bundle: bundle) }
    let identifier = await loader.load()

    #expect(identifier.isUnavailable)
    #expect(environment.apiBaseURL == URL(string: "https://api.fluke.test"))
    #expect(environment.configuration == .release)
  }

  @Test("on-device mode cache persists only the validated local mode")
  func identificationModeCache() async {
    let cache = IdentificationModeCache(store: MemoryBrowseCacheStore())

    await cache.record(.onDevice)
    #expect(await cache.load() == .onDevice)

    await cache.record(.server)
    #expect(await cache.load() == nil)
  }

  @Test("on-device mode survives relaunch through the validated file cache")
  func identificationModeSurvivesRelaunch() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = IdentificationModeCache(store: FileBrowseCacheStore(directory: directory))
    await first.record(.onDevice)

    let relaunched = IdentificationModeCache(store: FileBrowseCacheStore(directory: directory))

    #expect(await relaunched.load() == .onDevice)
  }

  @Test("an unapproved catalog leaves the one-shot loader unavailable")
  func unapprovedCatalogFailsClosed() async {
    let loader = OnDeviceIdentificationLoader {
      throw IdentifierArtifactError.incompatibleArtifact("rights")
    }

    #expect(await loader.load().isUnavailable)
    #expect(await loader.load().isUnavailable)
  }

  @Test("concurrent local identifier requests share one artifact load")
  func localIdentifierLoadsOnce() async {
    let recorder = IdentifierLoadRecorder()
    let loader = OnDeviceIdentificationLoader { try await recorder.load() }
    let tasks = (0..<8).map { _ in Task { await loader.load() } }
    await recorder.waitUntilRequested()
    for _ in 0..<20 { await Task.yield() }

    #expect(await recorder.count == 1)
    await recorder.resume()
    for task in tasks { _ = await task.value }
    _ = await loader.load()

    #expect(await recorder.count == 1)
  }

  private static func bundleWithoutCatalog() throws -> Bundle {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(UUID().uuidString).bundle", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let info: [String: Any] = [
      "CFBundleIdentifier": "app.fluke.tests.missing-catalog",
      "CFBundleName": "MissingCatalog",
      "CFBundlePackageType": "BNDL",
      "CFBundleShortVersionString": "1.0",
      "CFBundleVersion": "1",
    ]
    let data = try PropertyListSerialization.data(
      fromPropertyList: info,
      format: .xml,
      options: 0
    )
    try data.write(to: directory.appendingPathComponent("Info.plist"))
    return try #require(Bundle(url: directory))
  }
}

private actor IdentifierLoadRecorder {
  private(set) var count = 0
  private var continuations: [CheckedContinuation<any LocalIdentifying, any Error>] = []
  private var requestWaiters: [CheckedContinuation<Void, Never>] = []

  func load() async throws -> any LocalIdentifying {
    count += 1
    let ready = requestWaiters
    requestWaiters = []
    for waiter in ready { waiter.resume() }
    return try await withCheckedThrowingContinuation { continuations.append($0) }
  }

  func waitUntilRequested() async {
    guard count == 0 else { return }
    await withCheckedContinuation { requestWaiters.append($0) }
  }

  func resume() {
    let pending = continuations
    continuations = []
    for continuation in pending {
      continuation.resume(returning: AppNeverLocalIdentifier())
    }
  }
}

private struct AppNeverLocalIdentifier: LocalIdentifying {
  func identify(frame: CameraFrame) async throws -> LocalIdentificationState {
    throw CancellationError()
  }
}
