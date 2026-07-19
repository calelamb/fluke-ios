import FlukeKit
import FlukeML
import FlukeReleaseB
import Foundation
import Network
import OSLog

enum AppBuildConfiguration: String, CaseIterable {
  case debug
  case staging
  case release
}

enum AppConfigurationError: Error, Equatable {
  case insecureAPIBaseURL
  case invalidAPIBaseURL
  case localAPIBaseURL
  case missingAPIBaseURL
  case unknownBuildConfiguration
}

struct LaunchCapabilities: Equatable, Sendable {
  let accounts: Bool
  let identification: Bool
  let submissions: Bool
}

enum LaunchCapabilityState: Equatable, Sendable {
  case loading
  case available(LaunchCapabilities)
  case unavailable

  static func load(
    using fetch: () async throws -> Capabilities,
    retryDelaysNanoseconds: [UInt64] = [2_000_000_000, 5_000_000_000, 10_000_000_000],
    sleep: (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
  ) async -> LaunchCapabilityState {
    for attempt in 0...retryDelaysNanoseconds.count {
      if let capabilities = try? await fetch() {
        return .available(
          LaunchCapabilities(
            accounts: capabilities.accounts,
            identification: capabilities.identification,
            submissions: capabilities.submissions
          )
        )
      }
      guard attempt < retryDelaysNanoseconds.count else { break }
      do {
        try await sleep(retryDelaysNanoseconds[attempt])
      } catch {
        return .unavailable
      }
    }

    return .unavailable
  }
}

struct AppEnvironment {
  typealias CapabilitiesFetch = () async throws -> Capabilities
  typealias IdentifyServiceFactory = @MainActor @Sendable () -> any IdentifyServiceProtocol
  typealias SubmissionObservedAt = @MainActor @Sendable () -> Date

  let apiBaseURL: URL
  let authService: any AuthServiceProtocol
  let browseCacheStore: any BrowseCacheStore
  let configuration: AppBuildConfiguration
  let fetchCapabilities: CapabilitiesFetch
  let historicalSightingsRepository: HistoricalSightingsRepository
  let identifyServiceFactory: IdentifyServiceFactory
  let logbookRepository: any LogbookRepositoryProtocol
  let predictionRepository: PredictionRepository
  let sightingsRepository: SightingsRepository
  let sessionHintStore: any SessionHintStore
  let submissionQueue: SubmissionQueue
  let submissionObservedAt: SubmissionObservedAt
  let submissionService: any SubmissionServiceProtocol
  let whalesRepository: WhalesRepository

  static func live(bundle: Bundle = .main) throws -> AppEnvironment {
    guard
      let rawConfiguration = bundle.object(
        forInfoDictionaryKey: "FLUKE_BUILD_CONFIGURATION"
      ) as? String,
      let configuration = AppBuildConfiguration(rawValue: rawConfiguration)
    else {
      throw AppConfigurationError.unknownBuildConfiguration
    }

    return try make(
      apiBaseURLString: bundle.object(
        forInfoDictionaryKey: "FLUKE_API_BASE_URL"
      ) as? String,
      configuration: configuration,
      session: URLSession(configuration: submissionSessionConfiguration()),
      cacheStore: FileBrowseCacheStore(
        directory: FileBrowseCacheStore.liveDirectory()
      )
    )
  }

  static func make(
    apiBaseURLString: String?,
    configuration: AppBuildConfiguration,
    session: URLSession = .shared,
    capabilitiesFetch: CapabilitiesFetch? = nil,
    submissionObservedAt: @escaping SubmissionObservedAt = Date.init,
    cacheStore: any BrowseCacheStore = MemoryBrowseCacheStore()
  ) throws -> AppEnvironment {
    let apiBaseURL = try validatedAPIBaseURL(
      apiBaseURLString,
      configuration: configuration
    )
    let client = APIClient(baseURL: apiBaseURL, session: session)
    let submissionQueue = try SubmissionQueue()

    return AppEnvironment(
      apiBaseURL: apiBaseURL,
      authService: AuthService(api: client),
      browseCacheStore: cacheStore,
      configuration: configuration,
      fetchCapabilities: capabilitiesFetch ?? {
        try await client.get("/api/v1/capabilities")
      },
      historicalSightingsRepository: HistoricalSightingsRepository(api: client, cache: cacheStore),
      identifyServiceFactory: { IdentifyService(api: client) },
      logbookRepository: LogbookRepository(api: client),
      predictionRepository: PredictionRepository(api: client, cache: cacheStore),
      sightingsRepository: SightingsRepository(api: client, cache: cacheStore),
      sessionHintStore: KeychainSessionHintStore(),
      submissionQueue: submissionQueue,
      submissionObservedAt: submissionObservedAt,
      submissionService: SubmissionService(api: client),
      whalesRepository: WhalesRepository(api: client, cache: cacheStore)
    )
  }

  static func submissionSessionConfiguration() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.default
    configuration.waitsForConnectivity = true
    return configuration
  }

  private static func validatedAPIBaseURL(
    _ rawValue: String?,
    configuration: AppBuildConfiguration
  ) throws -> URL {
    guard let rawValue, !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw AppConfigurationError.missingAPIBaseURL
    }
    guard let components = URLComponents(string: rawValue),
      let scheme = components.scheme?.lowercased(),
      let host = components.host?.lowercased(),
      let url = components.url
    else {
      throw AppConfigurationError.invalidAPIBaseURL
    }

    let isLocal = isLocalHost(host)
    if configuration != .debug, isLocal {
      throw AppConfigurationError.localAPIBaseURL
    }
    if scheme != "https", !(configuration == .debug && isLocal && scheme == "http") {
      throw AppConfigurationError.insecureAPIBaseURL
    }

    return url
  }

  private static func isLocalHost(_ host: String) -> Bool {
    let normalizedHost =
      host
      .lowercased()
      .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    if normalizedHost == "localhost" || normalizedHost.hasSuffix(".localhost") {
      return true
    }

    let addressLiteral = normalizedHost.trimmingCharacters(
      in: CharacterSet(charactersIn: "[]")
    )
    if let address = IPv4Address(addressLiteral) {
      return address.rawValue.first == 127
    }
    guard let address = IPv6Address(addressLiteral) else {
      return false
    }

    let bytes = Array(address.rawValue)
    let isIPv6Loopback = bytes.dropLast().allSatisfy { $0 == 0 } && bytes.last == 1
    let isIPv4MappedLoopback =
      bytes.prefix(10).allSatisfy { $0 == 0 }
      && bytes[10] == 0xff
      && bytes[11] == 0xff
      && bytes[12] == 127
    return isIPv6Loopback || isIPv4MappedLoopback
  }
}

@MainActor
enum IdentifyComposition {
  static func resolve(
    enabled: Bool,
    factory: AppEnvironment.IdentifyServiceFactory
  ) -> (any IdentifyServiceProtocol)? {
    guard enabled else { return nil }
    return factory()
  }
}

enum OnDeviceIdentificationComposition {
  private static let logger = Logger(
    subsystem: "app.fluke",
    category: "on-device-identification"
  )

  static func load(bundle: Bundle = .main) async -> (any LocalIdentifying)? {
    do {
      return try await LocalIdentifier.load(bundle: bundle)
    } catch {
      logger.error("Local identifier unavailable: \(String(describing: error), privacy: .private)")
      return nil
    }
  }
}
