import Foundation
import Testing

@testable import Fluke

@MainActor
struct AppEnvironmentTests {
  @Test("Debug accepts an explicit localhost API URL")
  func debugAcceptsLocalhost() throws {
    let environment = try AppEnvironment.make(
      apiBaseURLString: "http://localhost:4000",
      configuration: .debug
    )

    #expect(environment.apiBaseURL == URL(string: "http://localhost:4000"))
  }

  @Test(
    "Staging and Release reject localhost API URLs",
    arguments: [
      AppBuildConfiguration.staging,
      AppBuildConfiguration.release,
    ])
  func nonDebugRejectsLocalhost(configuration: AppBuildConfiguration) {
    #expect(throws: AppConfigurationError.localAPIBaseURL) {
      try AppEnvironment.make(
        apiBaseURLString: "https://localhost",
        configuration: configuration
      )
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

  @Test("Production configuration accepts a remote HTTPS API URL")
  func releaseAcceptsHTTPS() throws {
    let environment = try AppEnvironment.make(
      apiBaseURLString: "https://api.fluke.test",
      configuration: .release
    )

    #expect(environment.apiBaseURL == URL(string: "https://api.fluke.test"))
  }
}
