import FlukeKit
import Foundation

public enum FeedProvider: String, Codable, CaseIterable, Sendable {
  case acartia
  case gbif
}

public enum FeedProviderStatus: String, Codable, Sendable {
  case neverRun = "NEVER_RUN"
  case started = "STARTED"
  case succeeded = "SUCCEEDED"
  case failed = "FAILED"
  case skippedLocked = "SKIPPED_LOCKED"
  case leaseLost = "LEASE_LOST"
}

public struct ProviderFreshness: Codable, Equatable, Sendable {
  public let expectedMaximumLag: Int
  public let lastAttemptAt: Date?
  public let lastSuccessAt: Date?
  public let provider: FeedProvider
  public let status: FeedProviderStatus

  public init(
    expectedMaximumLag: Int,
    lastAttemptAt: Date?,
    lastSuccessAt: Date?,
    provider: FeedProvider,
    status: FeedProviderStatus
  ) {
    self.expectedMaximumLag = expectedMaximumLag
    self.lastAttemptAt = lastAttemptAt
    self.lastSuccessAt = lastSuccessAt
    self.provider = provider
    self.status = status
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case expectedMaximumLag, lastAttemptAt, lastSuccessAt, provider, status
  }

  public init(from decoder: any Decoder) throws {
    try requireExactKeys(decoder, CodingKeys.allCases)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    expectedMaximumLag = try values.decode(Int.self, forKey: .expectedMaximumLag)
    lastAttemptAt = try values.decodeIfPresent(Date.self, forKey: .lastAttemptAt)
    lastSuccessAt = try values.decodeIfPresent(Date.self, forKey: .lastSuccessAt)
    provider = try values.decode(FeedProvider.self, forKey: .provider)
    status = try values.decode(FeedProviderStatus.self, forKey: .status)
    try require(
      (1...(31 * 24 * 60 * 60)).contains(expectedMaximumLag), decoder, "Invalid provider lag")
  }

  public func encode(to encoder: any Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(expectedMaximumLag, forKey: .expectedMaximumLag)
    try values.encode(lastAttemptAt, forKey: .lastAttemptAt)
    try values.encode(lastSuccessAt, forKey: .lastSuccessAt)
    try values.encode(provider, forKey: .provider)
    try values.encode(status, forKey: .status)
  }
}

public struct FeedSightingPhoto: Codable, Hashable, Sendable {
  public let id: String
  public let url: String
  public let thumbnailUrl: String
  public let orderIndex: Int

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case id, url, thumbnailUrl, orderIndex
  }

  public init(from decoder: any Decoder) throws {
    try requireExactKeys(decoder, CodingKeys.allCases)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(String.self, forKey: .id)
    url = try values.decode(String.self, forKey: .url)
    thumbnailUrl = try values.decode(String.self, forKey: .thumbnailUrl)
    orderIndex = try values.decode(Int.self, forKey: .orderIndex)
    try requireStableID(id, decoder)
    try requireHTTPURL(url, decoder)
    try requireHTTPURL(thumbnailUrl, decoder)
    try require((0..<1_000).contains(orderIndex), decoder, "Invalid photo order")
  }
}

public struct FeedIdentifiedWhale: Codable, Hashable, Sendable {
  public let catalogId: String
  public let name: String?
  public let confidence: IdentificationConfidence

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case catalogId, name, confidence
  }

  public init(from decoder: any Decoder) throws {
    try requireExactKeys(decoder, CodingKeys.allCases)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    catalogId = try values.decode(String.self, forKey: .catalogId)
    name = try values.decodeIfPresent(String.self, forKey: .name)
    confidence = try values.decode(IdentificationConfidence.self, forKey: .confidence)
    try requireStableID(catalogId, decoder)
    try requireBoundedText(name, decoder)
  }
}

public struct InternalFeedSighting: Codable, Hashable, Sendable {
  public let behaviorNotes: String?
  public let ecotypeGuess: Ecotype?
  public let groupSize: Int?
  public let id: String
  public let identifiedWhales: [FeedIdentifiedWhale]
  public let latitude: Double
  public let locationName: String?
  public let longitude: Double
  public let observedAt: Date
  public let photos: [FeedSightingPhoto]
  public let revision: Int

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case behaviorNotes, ecotypeGuess, groupSize, id, identifiedWhales, kind
    case latitude, locationName, longitude, observedAt, photos, revision
  }

  public init(from decoder: any Decoder) throws {
    try requireExactKeys(decoder, CodingKeys.allCases)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try values.decode(String.self, forKey: .kind)
    try require(kind == "internal", decoder, "Invalid item kind")
    behaviorNotes = try values.decodeIfPresent(String.self, forKey: .behaviorNotes)
    ecotypeGuess = try decodeEcotype(values, key: .ecotypeGuess, decoder: decoder)
    groupSize = try values.decodeIfPresent(Int.self, forKey: .groupSize)
    id = try values.decode(String.self, forKey: .id)
    identifiedWhales = try values.decode([FeedIdentifiedWhale].self, forKey: .identifiedWhales)
    latitude = try values.decode(Double.self, forKey: .latitude)
    locationName = try values.decodeIfPresent(String.self, forKey: .locationName)
    longitude = try values.decode(Double.self, forKey: .longitude)
    observedAt = try values.decode(Date.self, forKey: .observedAt)
    photos = try values.decode([FeedSightingPhoto].self, forKey: .photos)
    revision = try values.decode(Int.self, forKey: .revision)
    try validateFeedFields(
      id: id, revision: revision, latitude: latitude, longitude: longitude,
      groupSize: groupSize, nestedCounts: [identifiedWhales.count, photos.count], decoder: decoder
    )
    try requireBoundedText(behaviorNotes, decoder)
    try requireBoundedText(locationName, decoder)
  }

  public func encode(to encoder: any Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(behaviorNotes, forKey: .behaviorNotes)
    try values.encode(ecotypeGuess, forKey: .ecotypeGuess)
    try values.encode(groupSize, forKey: .groupSize)
    try values.encode(id, forKey: .id)
    try values.encode(identifiedWhales, forKey: .identifiedWhales)
    try values.encode("internal", forKey: .kind)
    try values.encode(latitude, forKey: .latitude)
    try values.encode(locationName, forKey: .locationName)
    try values.encode(longitude, forKey: .longitude)
    try values.encode(observedAt, forKey: .observedAt)
    try values.encode(photos, forKey: .photos)
    try values.encode(revision, forKey: .revision)
  }
}

public struct ExternalFeedSighting: Codable, Hashable, Sendable {
  public let attribution: String
  public let ecotypeGuess: Ecotype?
  public let groupSize: Int?
  public let id: String
  public let latitude: Double
  public let longitude: Double
  public let notes: String?
  public let observedAt: Date
  public let revision: Int
  public let source: String
  public let sourceUrl: String?
  public let species: String
  public let trusted: Bool

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case attribution, ecotypeGuess, groupSize, id, kind, latitude, longitude
    case notes, observedAt, revision, source, sourceUrl, species, trusted
  }

  public init(from decoder: any Decoder) throws {
    try requireExactKeys(decoder, CodingKeys.allCases)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try values.decode(String.self, forKey: .kind)
    try require(kind == "external", decoder, "Invalid item kind")
    attribution = try values.decode(String.self, forKey: .attribution)
    ecotypeGuess = try decodeEcotype(values, key: .ecotypeGuess, decoder: decoder)
    groupSize = try values.decodeIfPresent(Int.self, forKey: .groupSize)
    id = try values.decode(String.self, forKey: .id)
    latitude = try values.decode(Double.self, forKey: .latitude)
    longitude = try values.decode(Double.self, forKey: .longitude)
    notes = try values.decodeIfPresent(String.self, forKey: .notes)
    observedAt = try values.decode(Date.self, forKey: .observedAt)
    revision = try values.decode(Int.self, forKey: .revision)
    source = try values.decode(String.self, forKey: .source)
    sourceUrl = try values.decodeIfPresent(String.self, forKey: .sourceUrl)
    species = try values.decode(String.self, forKey: .species)
    trusted = try values.decode(Bool.self, forKey: .trusted)
    try validateFeedFields(
      id: id, revision: revision, latitude: latitude, longitude: longitude,
      groupSize: groupSize, nestedCounts: [], decoder: decoder
    )
    for value in [Optional(attribution), notes, Optional(source), Optional(species)] {
      try requireBoundedText(value, decoder)
    }
    if let sourceUrl { try requireHTTPURL(sourceUrl, decoder) }
  }

  public func encode(to encoder: any Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(attribution, forKey: .attribution)
    try values.encode(ecotypeGuess, forKey: .ecotypeGuess)
    try values.encode(groupSize, forKey: .groupSize)
    try values.encode(id, forKey: .id)
    try values.encode("external", forKey: .kind)
    try values.encode(latitude, forKey: .latitude)
    try values.encode(longitude, forKey: .longitude)
    try values.encode(notes, forKey: .notes)
    try values.encode(observedAt, forKey: .observedAt)
    try values.encode(revision, forKey: .revision)
    try values.encode(source, forKey: .source)
    try values.encode(sourceUrl, forKey: .sourceUrl)
    try values.encode(species, forKey: .species)
    try values.encode(trusted, forKey: .trusted)
  }
}

public struct RemovedFeedSighting: Codable, Hashable, Sendable {
  public let id: String
  public let revision: Int

  private enum CodingKeys: String, CodingKey, CaseIterable { case id, kind, revision }

  public init(from decoder: any Decoder) throws {
    try requireExactKeys(decoder, CodingKeys.allCases)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try values.decode(String.self, forKey: .kind)
    try require(kind == "removed", decoder, "Invalid item kind")
    id = try values.decode(String.self, forKey: .id)
    revision = try values.decode(Int.self, forKey: .revision)
    try requirePublicID(id, decoder)
    try requireRevision(revision, decoder)
  }

  public func encode(to encoder: any Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(id, forKey: .id)
    try values.encode("removed", forKey: .kind)
    try values.encode(revision, forKey: .revision)
  }
}

public enum SightingFeedItem: Codable, Hashable, Sendable, Identifiable {
  case `internal`(InternalFeedSighting)
  case external(ExternalFeedSighting)
  case removed(RemovedFeedSighting)

  public var id: String {
    switch self {
    case .internal(let value): value.id
    case .external(let value): value.id
    case .removed(let value): value.id
    }
  }
  public var revision: Int {
    switch self {
    case .internal(let value): value.revision
    case .external(let value): value.revision
    case .removed(let value): value.revision
    }
  }
  public var observedAt: Date? {
    switch self {
    case .internal(let value): value.observedAt
    case .external(let value): value.observedAt
    case .removed: nil
    }
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: KindKey.self)
    switch try values.decode(String.self, forKey: .kind) {
    case "internal": self = .internal(try InternalFeedSighting(from: decoder))
    case "external": self = .external(try ExternalFeedSighting(from: decoder))
    case "removed": self = .removed(try RemovedFeedSighting(from: decoder))
    default: throw corrupt(decoder, "Invalid item kind")
    }
  }

  public func encode(to encoder: any Encoder) throws {
    switch self {
    case .internal(let value): try value.encode(to: encoder)
    case .external(let value): try value.encode(to: encoder)
    case .removed(let value): try value.encode(to: encoder)
    }
  }

  private enum KindKey: String, CodingKey { case kind }
}

public struct SightingFeedPage: Decodable, Sendable {
  public let hasMore: Bool
  public let items: [SightingFeedItem]
  public let pageCursor: String?
  public let providers: [ProviderFreshness]
  public let syncCursor: String

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case hasMore, items, pageCursor, providers, syncCursor
  }

  public init(from decoder: any Decoder) throws {
    try requireExactKeys(decoder, CodingKeys.allCases)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    hasMore = try values.decode(Bool.self, forKey: .hasMore)
    items = try values.decode([SightingFeedItem].self, forKey: .items)
    pageCursor = try values.decodeIfPresent(String.self, forKey: .pageCursor)
    providers = try values.decode([ProviderFreshness].self, forKey: .providers)
    syncCursor = try values.decode(String.self, forKey: .syncCursor)
    try require(items.count <= 100, decoder, "Too many feed items")
    try require(
      providers.count == 2 && Set(providers.map(\.provider)).count == 2, decoder,
      "Invalid providers")
    try requireCursor(syncCursor, decoder)
    if let pageCursor { try requireCursor(pageCursor, decoder) }
    try require(hasMore || pageCursor == nil, decoder, "Unexpected terminal page cursor")
  }
}

public struct SightingFeedState: Codable, Equatable, Sendable {
  public static let maximumRetainedRevisions = 10_000

  public let items: [SightingFeedItem]
  public let tombstones: [String: Int]
  public let revisionFloor: Int
  public let syncCursor: String
  public let providers: [ProviderFreshness]

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case items, tombstones, revisionFloor, syncCursor, providers
  }

  public init(
    items: [SightingFeedItem],
    tombstones: [String: Int],
    revisionFloor: Int = 0,
    syncCursor: String,
    providers: [ProviderFreshness]
  ) {
    var active: [String: SightingFeedItem] = [:]
    for item in items where item.observedAt != nil {
      guard item.revision > (active[item.id]?.revision ?? 0) else { continue }
      active[item.id] = item
    }
    for (id, revision) in tombstones where revision >= (active[id]?.revision ?? Int.max) {
      active[id] = nil
    }
    let bounded = Self.bounded(active: active, tombstones: tombstones, floor: revisionFloor)
    self.items = Self.sorted(Array(bounded.active.values))
    self.tombstones = bounded.tombstones
    self.revisionFloor = bounded.floor
    self.syncCursor = syncCursor
    self.providers = providers
  }

  public init(from decoder: any Decoder) throws {
    try requireExactKeys(decoder, CodingKeys.allCases)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let decodedItems = try values.decode([SightingFeedItem].self, forKey: .items)
    let decodedTombstones = try values.decode([String: Int].self, forKey: .tombstones)
    let decodedFloor = try values.decode(Int.self, forKey: .revisionFloor)
    let decodedCursor = try values.decode(String.self, forKey: .syncCursor)
    let decodedProviders = try values.decode([ProviderFreshness].self, forKey: .providers)
    try require(
      decodedItems.allSatisfy { $0.observedAt != nil }, decoder, "Cached items contain tombstones")
    try require(
      decodedItems.count + decodedTombstones.count <= Self.maximumRetainedRevisions, decoder,
      "Cached state exceeds limit")
    try require(
      Set(decodedItems.map(\.id)).count == decodedItems.count, decoder,
      "Cached items contain duplicate IDs")
    try require(
      Set(decodedItems.map(\.id)).isDisjoint(with: decodedTombstones.keys), decoder,
      "Cached state overlaps active and removed IDs")
    try require(
      (0...9_007_199_254_740_991).contains(decodedFloor), decoder, "Invalid revision floor")
    for (id, revision) in decodedTombstones {
      try requirePublicID(id, decoder)
      try requireRevision(revision, decoder)
      try require(revision > decodedFloor, decoder, "Cached tombstone is below revision floor")
    }
    try require(
      decodedProviders.count == 2
        && Set(decodedProviders.map(\.provider)) == Set(FeedProvider.allCases),
      decoder,
      "Invalid cached providers"
    )
    try requireCursor(decodedCursor, decoder)
    self.init(
      items: decodedItems,
      tombstones: decodedTombstones,
      revisionFloor: decodedFloor,
      syncCursor: decodedCursor,
      providers: decodedProviders
    )
  }

  public func applying(
    items incoming: [SightingFeedItem], syncCursor: String, providers: [ProviderFreshness]
  ) -> Self {
    var active: [String: SightingFeedItem] = [:]
    for item in items where item.revision > (active[item.id]?.revision ?? 0) {
      active[item.id] = item
    }
    var removed = tombstones
    for item in incoming {
      let knownRevision = max(
        active[item.id]?.revision ?? revisionFloor, removed[item.id] ?? revisionFloor)
      guard item.revision > knownRevision else { continue }
      switch item {
      case .removed:
        active[item.id] = nil
        removed[item.id] = item.revision
      default:
        active[item.id] = item
        removed[item.id] = nil
      }
    }
    return Self(
      items: Array(active.values), tombstones: removed, revisionFloor: revisionFloor,
      syncCursor: syncCursor, providers: providers
    )
  }

  private static func bounded(
    active initialActive: [String: SightingFeedItem],
    tombstones initialTombstones: [String: Int],
    floor initialFloor: Int
  ) -> (active: [String: SightingFeedItem], tombstones: [String: Int], floor: Int) {
    var active = initialActive
    var tombstones = initialTombstones.filter { $0.value > initialFloor }
    var floor = initialFloor
    while active.count + tombstones.count > maximumRetainedRevisions {
      if let oldest = tombstones.min(by: { $0.value < $1.value }) {
        tombstones[oldest.key] = nil
        floor = max(floor, oldest.value)
      } else if let oldest = sorted(Array(active.values)).last {
        active[oldest.id] = nil
        floor = max(floor, oldest.revision)
      }
    }
    tombstones = tombstones.filter { $0.value > floor }
    return (active, tombstones, floor)
  }

  private static func sorted(_ items: [SightingFeedItem]) -> [SightingFeedItem] {
    items.sorted {
      guard $0.observedAt == $1.observedAt else {
        return ($0.observedAt ?? .distantPast) > ($1.observedAt ?? .distantPast)
      }
      return $0.id < $1.id
    }
  }
}

public enum SightingFeedFreshness: Equatable, Sendable {
  case live
  case recent(lastSuccessAge: Int?)

  public init(providers: [ProviderFreshness], now: Date) {
    let expected = Set(FeedProvider.allCases)
    let unique = Dictionary(grouping: providers, by: \.provider)
    let ages = providers.compactMap { value -> Int? in
      guard let success = value.lastSuccessAt else { return nil }
      return max(0, Int(now.timeIntervalSince(success)))
    }
    let allFresh =
      Set(unique.keys) == expected
      && unique.values.allSatisfy { values in
        guard values.count == 1, let value = values.first, let success = value.lastSuccessAt else {
          return false
        }
        let age = now.timeIntervalSince(success)
        return age >= -300 && age <= TimeInterval(value.expectedMaximumLag)
      }
    self = allFresh ? .live : .recent(lastSuccessAge: ages.max())
  }
}

private struct DynamicKey: CodingKey {
  let stringValue: String
  let intValue: Int? = nil
  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { return nil }
}

private func requireExactKeys<Key: CodingKey & CaseIterable>(_ decoder: any Decoder, _ keys: [Key])
  throws
{
  let values = try decoder.container(keyedBy: DynamicKey.self)
  try require(
    Set(values.allKeys.map(\.stringValue)) == Set(keys.map(\.stringValue)), decoder,
    "Unexpected or missing keys")
}

private func validateFeedFields(
  id: String, revision: Int, latitude: Double, longitude: Double, groupSize: Int?,
  nestedCounts: [Int], decoder: any Decoder
) throws {
  try requirePublicID(id, decoder)
  try requireRevision(revision, decoder)
  try require(latitude.isFinite && (-90...90).contains(latitude), decoder, "Invalid latitude")
  try require(longitude.isFinite && (-180...180).contains(longitude), decoder, "Invalid longitude")
  try require(groupSize.map { (1...200).contains($0) } ?? true, decoder, "Invalid group size")
  try require(nestedCounts.allSatisfy { $0 <= 1_000 }, decoder, "Too many nested values")
}

private func requirePublicID(_ value: String, _ decoder: any Decoder) throws {
  try require(
    !value.isEmpty && value.utf16.count <= 2_710 && value.contains(where: { !$0.isWhitespace }),
    decoder, "Invalid feed ID")
}
private func requireStableID(_ value: String, _ decoder: any Decoder) throws {
  try require(
    !value.isEmpty && value.utf16.count <= 200 && value.contains(where: { !$0.isWhitespace }),
    decoder, "Invalid stable ID")
}
private func requireRevision(_ value: Int, _ decoder: any Decoder) throws {
  try require((1...9_007_199_254_740_991).contains(value), decoder, "Invalid revision")
}
private func requireCursor(_ value: String, _ decoder: any Decoder) throws {
  try require(!value.isEmpty && value.utf16.count <= 512, decoder, "Invalid cursor")
}
private func requireBoundedText(_ value: String?, _ decoder: any Decoder) throws {
  try require(value.map { $0.utf16.count <= 20_000 } ?? true, decoder, "Text exceeds limit")
}
private func requireHTTPURL(_ value: String, _ decoder: any Decoder) throws {
  let components = URLComponents(string: value)
  let scheme = components?.scheme?.lowercased()
  let hasHost = components?.host?.isEmpty == false
  try require(
    value.utf16.count <= 2_048 && hasHost && (scheme == "http" || scheme == "https"), decoder,
    "Invalid HTTP URL")
}

private func decodeEcotype<Key: CodingKey>(
  _ values: KeyedDecodingContainer<Key>,
  key: Key,
  decoder: any Decoder
) throws -> Ecotype? {
  if try values.decodeNil(forKey: key) { return nil }
  let rawValue = try values.decode(String.self, forKey: key)
  guard let value = Ecotype(rawValue: rawValue) else { throw corrupt(decoder, "Invalid ecotype") }
  return value
}
private func require(
  _ condition: @autoclosure () -> Bool, _ decoder: any Decoder, _ message: String
) throws {
  guard condition() else { throw corrupt(decoder, message) }
}
private func corrupt(_ decoder: any Decoder, _ message: String) -> DecodingError {
  .dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: message))
}
