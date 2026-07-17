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
      configuration: .debug
    )

    #expect(environment.apiBaseURL == URL(string: "http://localhost:4000"))
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
}
