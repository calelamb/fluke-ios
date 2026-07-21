import FlukeKit
import Foundation

#if DEBUG || FLUKE_XCTEST_FIXTURES
enum AppStoreScreenshotFixtureMode {
  static let launchArgument = "-FlukeXCTestAppStoreFixtures"

  static func isEnabled(
    arguments: [String] = ProcessInfo.processInfo.arguments,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Bool {
    let fixtureEnvironmentEnabled = environment["FLUKE_XCTEST_FIXTURES"] == "1"
    return fixtureEnvironmentEnabled && arguments.contains(launchArgument)
  }
}

enum AppStoreScreenshotFixtures {
  // Preview fixture: identification is disabled, so screenshots cannot imply a production match.
  static func makeEnvironment() throws -> AppEnvironment {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AppStoreScreenshotURLProtocol.self]
    configuration.httpCookieStorage = HTTPCookieStorage()

    return try AppEnvironment.make(
      apiBaseURLString: "https://app-store-fixtures.fluke.invalid",
      configuration: .debug,
      session: URLSession(configuration: configuration),
      submissionObservedAt: { Date(timeIntervalSince1970: 1_784_224_800) },
      cacheStore: MemoryBrowseCacheStore()
    )
  }
}

private final class AppStoreScreenshotURLProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "app-store-fixtures.fluke.invalid"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let url = request.url else {
      client?.urlProtocol(self, didFailWithError: URLError(.badURL))
      return
    }
    let fixture = Self.fixture(method: request.httpMethod ?? "GET", path: url.path)
    guard let response = HTTPURLResponse(
      url: url,
      statusCode: fixture.statusCode,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
    ) else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: fixture.data)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}

  private static func fixture(method: String, path: String) -> (statusCode: Int, data: Data) {
    guard method == "GET" else { return error(statusCode: 405, code: "FIXTURE_READ_ONLY") }
    switch path {
    case "/api/v1/capabilities": return response(capabilities)
    case "/api/v1/sighting-feed": return response(sightingFeed)
    case "/api/v1/sightings": return response(sightings)
    case "/api/v1/external-sightings": return response(externalSightings)
    case "/api/v1/whales": return response(whales)
    case "/api/v1/sightings/historical": return response(historicalSightings)
    case "/api/v1/predict": return response(prediction)
    case "/api/v1/auth/me": return error(statusCode: 401, code: "UNAUTHENTICATED")
    default: return error(statusCode: 404, code: "FIXTURE_NOT_FOUND")
    }
  }

  private static func response(_ json: String) -> (statusCode: Int, data: Data) {
    (200, Data(json.utf8))
  }

  private static func error(statusCode: Int, code: String) -> (statusCode: Int, data: Data) {
    let json = #"{"code":"\#(code)","message":"Fixture request unavailable.","requestId":"app-store-fixture","retryable":false}"#
    return (statusCode, Data(json.utf8))
  }

  private static let capabilities =
    #"{"accounts":true,"identification":false,"submissions":true}"#

  private static let sightingFeed = #"""
    {
      "hasMore": false,
      "items": [
        {
          "behaviorNotes": "Traveling north in a close group.",
          "ecotypeGuess": "RESIDENT",
          "groupSize": 5,
          "id": "app-store-sighting-1",
          "identifiedWhales": [{"catalogId":"J35","confidence":"CONFIRMED","name":"Tahlequah"}],
          "kind": "internal",
          "latitude": 48.52,
          "locationName": "Salish Sea",
          "longitude": -123.11,
          "observedAt": "2026-07-16T18:00:00.000Z",
          "photos": [],
          "revision": 3
        },
        {
          "behaviorNotes": "Foraging along the island shelf.",
          "ecotypeGuess": "RESIDENT",
          "groupSize": 3,
          "id": "app-store-sighting-2",
          "identifiedWhales": [{"catalogId":"J27","confidence":"LIKELY","name":"Blackberry"}],
          "kind": "internal",
          "latitude": 48.60,
          "locationName": "Haro Strait",
          "longitude": -123.18,
          "observedAt": "2026-07-15T16:20:00.000Z",
          "photos": [],
          "revision": 2
        },
        {
          "attribution": "Conserve.io / Spotter-API",
          "ecotypeGuess": "BIGGS",
          "groupSize": 4,
          "id": "external:acartia:app-store-fixture-1",
          "kind": "external",
          "latitude": 48.31,
          "longitude": -122.68,
          "notes": "Steady travel past the lighthouse.",
          "observedAt": "2026-07-14T20:45:00.000Z",
          "revision": 1,
          "source": "acartia",
          "sourceUrl": "https://acartia.io",
          "species": "Orcinus orca",
          "trusted": true
        }
      ],
      "pageCursor": null,
      "providers": [
        {"expectedMaximumLag":25200,"lastAttemptAt":"2026-07-16T17:40:00.000Z","lastSuccessAt":"2026-07-16T17:40:00.000Z","provider":"acartia","status":"SUCCEEDED"},
        {"expectedMaximumLag":691200,"lastAttemptAt":"2026-07-16T12:00:00.000Z","lastSuccessAt":"2026-07-16T12:00:00.000Z","provider":"gbif","status":"SUCCEEDED"}
      ],
      "syncCursor": "fixture-r3"
    }
    """#

  private static let sightings = #"""
    {
      "items": [
        {
          "behaviorNotes": "Traveling north in a close group.",
          "ecotypeGuess": "RESIDENT",
          "groupSize": 5,
          "id": "app-store-sighting-1",
          "identifiedWhales": [{"catalogId":"J35","confidence":"CONFIRMED","name":"Tahlequah"}],
          "latitude": 48.52,
          "locationName": "Salish Sea",
          "longitude": -123.11,
          "observedAt": "2026-07-16T18:00:00.000Z",
          "photoUrls": [],
          "photos": [],
          "status": "APPROVED"
        },
        {
          "behaviorNotes": "Foraging along the island shelf.",
          "ecotypeGuess": "RESIDENT",
          "groupSize": 3,
          "id": "app-store-sighting-2",
          "identifiedWhales": [{"catalogId":"J27","confidence":"LIKELY","name":"Blackberry"}],
          "latitude": 48.60,
          "locationName": "Haro Strait",
          "longitude": -123.18,
          "observedAt": "2026-07-15T16:20:00.000Z",
          "photoUrls": [],
          "photos": [],
          "status": "APPROVED"
        },
        {
          "behaviorNotes": "Steady travel past the lighthouse.",
          "ecotypeGuess": "BIGGS",
          "groupSize": 4,
          "id": "app-store-sighting-3",
          "identifiedWhales": [],
          "latitude": 48.31,
          "locationName": "Admiralty Inlet",
          "longitude": -122.68,
          "observedAt": "2026-07-14T20:45:00.000Z",
          "photoUrls": [],
          "photos": [],
          "status": "APPROVED"
        }
      ],
      "page": {"hasMore":false,"nextCursor":null}
    }
    """#

  private static let externalSightings =
    #"{"items":[],"page":{"hasMore":false,"nextCursor":null}}"#

  private static let whales = #"""
    {
      "items": [
        {
          "biography":"A matriline leader known throughout the Salish Sea.",
          "birthYear":1998,
          "catalogId":"J35",
          "deathYear":null,
          "distinguishingMarks":"A familiar saddle patch and dorsal profile.",
          "ecotype":"RESIDENT",
          "heroImageUrl":null,
          "id":"whale-j35",
          "name":"Tahlequah",
          "notableEvents":[],
          "pod":"J",
          "sex":"FEMALE",
          "sourceCitations":[],
          "status":"ALIVE"
        },
        {
          "biography":"An adult male frequently observed traveling with J Pod.",
          "birthYear":1991,
          "catalogId":"J27",
          "deathYear":null,
          "distinguishingMarks":"Tall dorsal fin with a distinctive trailing edge.",
          "ecotype":"RESIDENT",
          "heroImageUrl":null,
          "id":"whale-j27",
          "name":"Blackberry",
          "notableEvents":[],
          "pod":"J",
          "sex":"MALE",
          "sourceCitations":[],
          "status":"ALIVE"
        },
        {
          "biography":"A Bigg's killer whale documented across inland waters.",
          "birthYear":1994,
          "catalogId":"T49A",
          "deathYear":null,
          "distinguishingMarks":"Broad fin and open saddle patch.",
          "ecotype":"BIGGS",
          "heroImageUrl":null,
          "id":"whale-t49a",
          "name":"Nan",
          "notableEvents":[],
          "pod":null,
          "sex":"FEMALE",
          "sourceCitations":[],
          "status":"ALIVE"
        }
      ],
      "page":{"hasMore":false,"nextCursor":null}
    }
    """#

  private static let historicalSightings = #"""
    {
      "items":[
        {"ecotypeGuess":"RESIDENT","id":"history-1","latitude":48.32,"locationName":"Admiralty Inlet","longitude":-122.68,"observedAt":"2026-07-12T18:00:00.000Z","whaleIds":["J35"]},
        {"ecotypeGuess":"RESIDENT","id":"history-2","latitude":48.46,"locationName":"San Juan Channel","longitude":-122.98,"observedAt":"2026-07-13T18:00:00.000Z","whaleIds":["J35","J27"]},
        {"ecotypeGuess":"RESIDENT","id":"history-3","latitude":48.60,"locationName":"Haro Strait","longitude":-123.18,"observedAt":"2026-07-14T18:00:00.000Z","whaleIds":["J27"]}
      ],
      "page":{"hasMore":false,"nextCursor":null}
    }
    """#

  private static let prediction = #"""
    {
      "cells":[
        {"lat":48.52,"lng":-123.11,"probability":0.72},
        {"lat":48.60,"lng":-123.18,"probability":0.58}
      ],
      "computedAt":"2026-07-16T18:00:00.000Z",
      "confidence":0.68,
      "modelVersion":"app-store-fixture-v1"
    }
    """#
}
#endif
