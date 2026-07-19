import FlukeKit
import Foundation

public protocol LogbookRepositoryProtocol: Sendable {
  func load() async throws -> [LogbookEntry]
}

public struct LogbookRepository: LogbookRepositoryProtocol, Sendable {
  private static let maximumCursorLength = 512
  private static let maximumItemCount = 10_000
  private static let maximumPageCount = 100
  private static let maximumPageItemCount = 100

  private let api: APIClient

  public init(api: APIClient) {
    self.api = api
  }

  public func load() async throws -> [LogbookEntry] {
    try await loadPage(cursor: nil, pageCount: 0, seenCursors: [], sightings: [])
      .map(\.logbookEntry)
  }

  private func loadPage(
    cursor: String?,
    pageCount: Int,
    seenCursors: Set<String>,
    sightings: [OwnerSighting]
  ) async throws -> [OwnerSighting] {
    try Task.checkCancellation()
    guard pageCount < Self.maximumPageCount else { throw APIError.invalidPagination }
    let response: OwnerSightingPage = try await api.get(Self.request(cursor: cursor))
    guard response.items.count <= Self.maximumPageItemCount,
      response.items.count <= Self.maximumItemCount - sightings.count
    else { throw APIError.invalidPagination }
    let accumulated = sightings + response.items
    guard response.page.hasMore else {
      guard response.page.nextCursor == nil else { throw APIError.invalidPagination }
      return accumulated
    }
    let nextCursor = try Self.validatedNextCursor(response.page.nextCursor, seen: seenCursors)
    return try await loadPage(
      cursor: nextCursor,
      pageCount: pageCount + 1,
      seenCursors: seenCursors.union([nextCursor]),
      sightings: accumulated
    )
  }

  private static func request(cursor: String?) -> APIRequest {
    APIRequest(
      path: ReleaseBEndpoint.mySightings,
      queryItems: cursor.map { [URLQueryItem(name: "cursor", value: $0)] } ?? []
    )
  }

  private static func validatedNextCursor(_ cursor: String?, seen: Set<String>) throws -> String {
    guard let cursor, !cursor.isEmpty, cursor.utf16.count <= maximumCursorLength,
      !seen.contains(cursor)
    else { throw APIError.invalidPagination }
    return cursor
  }
}

private struct OwnerSightingPage: Decodable, Sendable {
  let items: [OwnerSighting]
  let page: OwnerPageMetadata

  private enum CodingKeys: String, CodingKey, CaseIterable { case items, page }

  init(from decoder: any Decoder) throws {
    try requireExactLogbookKeys(decoder, CodingKeys.allCases)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    items = try values.decode([OwnerSighting].self, forKey: .items)
    page = try values.decode(OwnerPageMetadata.self, forKey: .page)
  }
}

private struct OwnerPageMetadata: Decodable, Sendable {
  let hasMore: Bool
  let nextCursor: String?

  private enum CodingKeys: String, CodingKey, CaseIterable { case hasMore, nextCursor }

  init(from decoder: any Decoder) throws {
    try requireExactLogbookKeys(decoder, CodingKeys.allCases)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    hasMore = try values.decode(Bool.self, forKey: .hasMore)
    nextCursor = try values.decodeIfPresent(String.self, forKey: .nextCursor)
  }
}

private struct OwnerSighting: Decodable, Hashable, Sendable {
  let behaviorNotes: String?
  let createdAt: Date
  let ecotypeGuess: Ecotype?
  let groupSize: Int?
  let id: String
  let latitude: Double
  let locationName: String?
  let longitude: Double
  let observedAt: Date
  let photoCount: Int
  let rejectionReason: String?
  let status: SightingStatus

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case behaviorNotes, createdAt, ecotypeGuess, groupSize, id, latitude, locationName, longitude
    case observedAt, photoCount, rejectionReason, status
  }

  init(from decoder: any Decoder) throws {
    try requireExactLogbookKeys(decoder, CodingKeys.allCases)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    behaviorNotes = try values.decodeIfPresent(String.self, forKey: .behaviorNotes)
    createdAt = try values.decode(Date.self, forKey: .createdAt)
    ecotypeGuess = try values.decodeIfPresent(Ecotype.self, forKey: .ecotypeGuess)
    groupSize = try values.decodeIfPresent(Int.self, forKey: .groupSize)
    id = try values.decode(String.self, forKey: .id)
    latitude = try values.decode(Double.self, forKey: .latitude)
    locationName = try values.decodeIfPresent(String.self, forKey: .locationName)
    longitude = try values.decode(Double.self, forKey: .longitude)
    observedAt = try values.decode(Date.self, forKey: .observedAt)
    photoCount = try values.decode(Int.self, forKey: .photoCount)
    rejectionReason = try values.decodeIfPresent(String.self, forKey: .rejectionReason)
    status = try values.decode(SightingStatus.self, forKey: .status)
  }

  var logbookEntry: LogbookEntry {
    LogbookEntry(
      id: id,
      observedAt: observedAt,
      locationName: locationName,
      status: logbookStatus,
      createdAt: createdAt,
      photoCount: photoCount,
      rejectionReason: rejectionReason
    )
  }

  private var logbookStatus: LogbookStatus {
    switch status {
    case .pending: .pending
    case .approved: .approved
    case .rejected: .rejected
    }
  }
}

private struct LogbookDynamicCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int? = nil

  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { nil }
}

private func requireExactLogbookKeys<Key: CodingKey>(
  _ decoder: any Decoder,
  _ keys: [Key]
) throws {
  let dynamic = try decoder.container(keyedBy: LogbookDynamicCodingKey.self)
  guard Set(dynamic.allKeys.map(\.stringValue)) == Set(keys.map(\.stringValue)) else {
    throw DecodingError.dataCorrupted(
      .init(codingPath: decoder.codingPath, debugDescription: "Unexpected owner sighting keys")
    )
  }
}
