import FlukeUI
import SwiftUI

@main
struct FlukeApp: App {
  static let preferredColorScheme: ColorScheme? = .light

  private let bootstrap: AppBootstrap

  init() {
    FlukeUIFontRegistration.registerIfNeeded()
    bootstrap = AppBootstrap.load()
  }

  var body: some Scene {
    WindowGroup {
      Group {
        switch bootstrap {
        case .ready(let environment):
          RootScene(environment: environment)
        case .unavailable:
          ConfigurationUnavailableView()
        }
      }
      .preferredColorScheme(Self.preferredColorScheme)
    }
  }
}

private enum AppBootstrap {
  case ready(AppEnvironment)
  case unavailable

  static func load() -> AppBootstrap {
    do {
      #if DEBUG || FLUKE_XCTEST_FIXTURES
        if AppStoreScreenshotFixtureMode.isEnabled() {
          return .ready(try AppStoreScreenshotFixtures.makeEnvironment())
        }
      #endif
      return .ready(try AppEnvironment.live())
    } catch {
      return .unavailable
    }
  }
}

private struct ConfigurationUnavailableView: View {
  var body: some View {
    ContentUnavailableView(
      "Fluke is unavailable",
      systemImage: "exclamationmark.triangle",
      description: Text("The app configuration could not be loaded safely.")
    )
  }
}
