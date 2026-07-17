import SwiftUI

@main
struct FlukeApp: App {
  private let bootstrap = AppBootstrap.load()

  var body: some Scene {
    WindowGroup {
      switch bootstrap {
      case .ready(let environment):
        RootScene(environment: environment)
      case .unavailable:
        ConfigurationUnavailableView()
      }
    }
  }
}

private enum AppBootstrap {
  case ready(AppEnvironment)
  case unavailable

  static func load() -> AppBootstrap {
    do {
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
