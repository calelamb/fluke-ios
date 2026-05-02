import XCTest
@testable import FlukeKit

final class PredictionTypesTests: XCTestCase {

    func test_predictionCell_decodesFromJSON() throws {
        let json = """
        {"lat": 48.5, "lng": -123.1, "probability": 0.42}
        """.data(using: .utf8)!
        let cell = try JSONDecoder().decode(PredictionCell.self, from: json)
        XCTAssertEqual(cell.lat, 48.5)
        XCTAssertEqual(cell.lng, -123.1)
        XCTAssertEqual(cell.probability, 0.42, accuracy: 0.001)
    }

    func test_prediction_decodesFullShape() throws {
        let json = """
        {
          "cells": [{"lat": 48.5, "lng": -123.0, "probability": 0.5}],
          "confidence": 0.8,
          "modelVersion": "markov-v1",
          "computedAt": "2026-05-01T18:00:00.000Z"
        }
        """.data(using: .utf8)!
        let p = try JSONDecoder.fluke.decode(Prediction.self, from: json)
        XCTAssertEqual(p.cells.count, 1)
        XCTAssertEqual(p.confidence, 0.8, accuracy: 0.001)
        XCTAssertEqual(p.modelVersion, "markov-v1")
    }

    func test_predictionHorizon_displayNames() {
        XCTAssertEqual(PredictionHorizon.h24.displayName, "24h")
        XCTAssertEqual(PredictionHorizon.d7.displayName, "7 days")
        XCTAssertEqual(PredictionHorizon.d30.displayName, "30 days")
    }
}
