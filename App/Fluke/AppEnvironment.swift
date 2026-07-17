import FlukeKit
import Foundation
import Network

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

struct ReleaseACapabilityState: Equatable {
  let accounts: Bool
  let identification: Bool
  let submissions: Bool

  static let disabled = ReleaseACapabilityState(
    accounts: false,
    identification: false,
    submissions: false
  )

  static func load(
    using fetch: () async throws -> Capabilities
  ) async -> ReleaseACapabilityState {
    guard let capabilities = try? await fetch(),
      !capabilities.accounts,
      !capabilities.identification,
      !capabilities.submissions
    else {
      return .disabled
    }

    return ReleaseACapabilityState(
      accounts: capabilities.accounts,
      identification: capabilities.identification,
      submissions: capabilities.submissions
    )
  }
}

struct AppEnvironment {
  typealias CapabilitiesFetch = () async throws -> Capabilities

  let apiBaseURL: URL
  let browseCacheStore: any BrowseCacheStore
  let configuration: AppBuildConfiguration
  let fetchCapabilities: CapabilitiesFetch
  let historicalSightingsRepository: HistoricalSightingsRepository
  let predictionRepository: PredictionRepository
  let sightingsRepository: SightingsRepository
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
    cacheStore: any BrowseCacheStore = MemoryBrowseCacheStore()
  ) throws -> AppEnvironment {
    let apiBaseURL = try validatedAPIBaseURL(
      apiBaseURLString,
      configuration: configuration
    )
    let client = APIClient(baseURL: apiBaseURL, session: session)

    return AppEnvironment(
      apiBaseURL: apiBaseURL,
      browseCacheStore: cacheStore,
      configuration: configuration,
      fetchCapabilities: capabilitiesFetch ?? {
        try await client.get("/api/v1/capabilities")
      },
      historicalSightingsRepository: HistoricalSightingsRepository(api: client, cache: cacheStore),
      predictionRepository: PredictionRepository(api: client, cache: cacheStore),
      sightingsRepository: SightingsRepository(api: client, cache: cacheStore),
      whalesRepository: WhalesRepository(api: client, cache: cacheStore)
    )
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
