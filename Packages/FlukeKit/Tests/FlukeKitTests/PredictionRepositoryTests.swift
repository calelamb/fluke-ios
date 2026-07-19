import XCTest
@testable import FlukeKit

final class PredictionRepositoryTests: XCTestCase {

    private var apiClient: APIClient!
    private var repo: PredictionRepository!

    override func setUp() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        apiClient = APIClient(baseURL: URL(string: "http://localhost:4000")!, session: session)
        repo = PredictionRepository(api: apiClient)
    }

    override func tearDown() async throws {
        MockURLProtocol.reset()
    }

    func test_fetch_decodesPredictionForWhale() async throws {
        MockURLProtocol.install { req in
            XCTAssertEqual(req.url?.path, "/api/v1/predict")
            XCTAssertEqual(req.url?.query, "whaleId=wh_a&horizon=24h")
            let body = """
            {
              "cells": [{"lat":48.5,"lng":-123.0,"probability":0.5}],
              "confidence": 0.8,
              "modelVersion": "markov-v1",
              "computedAt": "2026-05-01T18:00:00.000Z"
            }
            """.data(using: .utf8)!
            return (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                body
            )
        }
        let prediction = try await repo.fetch(subject: .whale(id: "wh_a"), horizon: .h24)
        XCTAssertNotNil(prediction)
        XCTAssertEqual(prediction?.cells.count, 1)
        XCTAssertEqual(prediction?.modelVersion, "markov-v1")
    }

    func test_fetch_returnsNilOn404() async throws {
        MockURLProtocol.install { req in
            (
                HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!,
                #"{"error":"not found"}"#.data(using: .utf8)!
            )
        }
        let prediction = try await repo.fetch(subject: .pod(.j), horizon: .d7)
        XCTAssertNil(prediction)
    }

    func test_fetch_includesPodInQueryString() async throws {
        MockURLProtocol.install { req in
            XCTAssertEqual(req.url?.query, "pod=BIGGS&horizon=30d")
            let body = """
            {"cells":[],"confidence":0.0,"modelVersion":"markov-v1","computedAt":"2026-05-01T18:00:00.000Z"}
            """.data(using: .utf8)!
            return (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                body
            )
        }
        let _ = try await repo.fetch(subject: .pod(.biggs), horizon: .d30)
    }
}
