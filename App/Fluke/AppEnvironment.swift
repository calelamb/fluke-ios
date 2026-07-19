import FlukeFeatures
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
  let identificationMode: IdentificationMode
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
            identificationMode: capabilities.identificationMode,
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
  typealias SubmissionObservedAt = @MainActor @Sendable () -> Date

  let apiBaseURL: URL
  let authService: any AuthServiceProtocol
  let browseCacheStore: any BrowseCacheStore
  let configuration: AppBuildConfiguration
  let fetchCapabilities: CapabilitiesFetch
  let historicalSightingsRepository: HistoricalSightingsRepository
  let identificationModeCache: IdentificationModeCache
  let localIdentifierLoader: OnDeviceIdentificationLoader
  let logbookRepository: any LogbookRepositoryProtocol
  let predictionRepository: PredictionRepository
  let sightingsRepository: SightingsRepository
  let sightingFeedRepository: SightingFeedRepository
  let sessionHintStore: any SessionHintStore
  let submissionQueue: SubmissionQueue
  let submissionObservedAt: SubmissionObservedAt
  let submissionService: any SubmissionServiceProtocol
  let submissionInvalidationHub: SubmissionInvalidationHub
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
      ),
      localIdentifierLoad: { try await LocalIdentifier.load(bundle: bundle) }
    )
  }

  static func make(
    apiBaseURLString: String?,
    configuration: AppBuildConfiguration,
    session: URLSession = .shared,
    capabilitiesFetch: CapabilitiesFetch? = nil,
    authService: (any AuthServiceProtocol)? = nil,
    submissionObservedAt: @escaping SubmissionObservedAt = Date.init,
    cacheStore: any BrowseCacheStore = MemoryBrowseCacheStore(),
    localIdentifierLoad: @escaping OnDeviceIdentificationLoader.Load = {
      try await LocalIdentifier.load(bundle: .main)
    }
  ) throws -> AppEnvironment {
    let apiBaseURL = try validatedAPIBaseURL(
      apiBaseURLString,
      configuration: configuration
    )
    let client = APIClient(baseURL: apiBaseURL, session: session)
    let submissionQueue = try SubmissionQueue()
    let submissionInvalidationHub = SubmissionInvalidationHub()

    return AppEnvironment(
      apiBaseURL: apiBaseURL,
      authService: authService ?? AuthService(api: client),
      browseCacheStore: cacheStore,
      configuration: configuration,
      fetchCapabilities: capabilitiesFetch ?? {
        try await client.get("/api/v1/capabilities")
      },
      historicalSightingsRepository: HistoricalSightingsRepository(api: client, cache: cacheStore),
      identificationModeCache: IdentificationModeCache(store: cacheStore),
      localIdentifierLoader: OnDeviceIdentificationLoader(load: localIdentifierLoad),
      logbookRepository: LogbookRepository(api: client),
      predictionRepository: PredictionRepository(api: client, cache: cacheStore),
      sightingsRepository: SightingsRepository(api: client, cache: cacheStore),
      sightingFeedRepository: SightingFeedRepository(api: client, cache: cacheStore),
      sessionHintStore: KeychainSessionHintStore(),
      submissionQueue: submissionQueue,
      submissionObservedAt: submissionObservedAt,
      submissionService: SubmissionService(api: client),
      submissionInvalidationHub: submissionInvalidationHub,
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

actor IdentificationModeCache {
  private static let key = BrowseCacheKey(resource: "identification-mode", identity: "launch")
  private static let logger = Logger(
    subsystem: "app.fluke",
    category: "identification-mode-cache"
  )
  private let store: any BrowseCacheStore

  init(store: any BrowseCacheStore) { self.store = store }

  func load() async -> IdentificationMode? {
    do {
      guard
        let document = try await store.load(IdentificationMode.self, for: Self.key),
        case .value(.onDevice) = document.payload
      else { return nil }
      return .onDevice
    } catch {
      Self.logger.error(
        "Identification mode cache unavailable: \(String(describing: error), privacy: .private)"
      )
      return nil
    }
  }

  func record(_ mode: IdentificationMode) async {
    do {
      guard mode == .onDevice else {
        try await store.remove(Self.key)
        return
      }
      try await store.replace(
        BrowseCacheDocument(
          resource: Self.key.resource,
          fetchedAt: Date(),
          payload: .value(mode)
        ),
        for: Self.key
      )
    } catch {
      Self.logger.error(
        "Identification mode cache write failed: \(String(describing: error), privacy: .private)"
      )
    }
  }
}

enum LocalIdentifierAvailability: Sendable {
  case available(any LocalIdentifying)
  case unavailable

  var isUnavailable: Bool {
    guard case .unavailable = self else { return false }
    return true
  }
}

actor OnDeviceIdentificationLoader {
  typealias Load = @Sendable () async throws -> any LocalIdentifying

  private static let logger = Logger(
    subsystem: "app.fluke",
    category: "on-device-identification"
  )

  private let loadIdentifier: Load
  private var loaded: LocalIdentifierAvailability?
  private var inFlight: Task<LocalIdentifierAvailability, Never>?

  init(load: @escaping Load) { loadIdentifier = load }

  func load() async -> LocalIdentifierAvailability {
    if let loaded { return loaded }
    if let inFlight { return await inFlight.value }
    let loadIdentifier = self.loadIdentifier
    let task = Task<LocalIdentifierAvailability, Never> {
      do {
        return .available(try await loadIdentifier())
      } catch {
        Self.logger.error(
          "Verified local identifier unavailable: \(String(describing: error), privacy: .private)"
        )
        return .unavailable
      }
    }
    inFlight = task
    let result = await task.value
    loaded = result
    inFlight = nil
    return result
  }
}

enum IdentificationComposition {
  static func resolve(
    capabilities: LaunchCapabilityState,
    cachedMode: IdentificationMode?,
    localIdentifier: LocalIdentifierAvailability
  ) -> IdentifyCapability {
    switch effectiveMode(capabilities: capabilities, cachedMode: cachedMode) {
    case .disabled:
      return .cameraOnly(.notEnabledForRelease)
    case .server:
      return .unavailable(.serverUnsupported)
    case .onDevice:
      guard case .available(let identifier) = localIdentifier else {
        return .cameraOnly(.artifactsUnavailable)
      }
      return .onDevice(identifier)
    }
  }

  static func effectiveMode(
    capabilities: LaunchCapabilityState,
    cachedMode: IdentificationMode?
  ) -> IdentificationMode {
    guard case .available(let value) = capabilities else {
      return cachedMode == .onDevice ? .onDevice : .disabled
    }
    guard value.identification else { return .disabled }
    return value.identificationMode
  }
}
