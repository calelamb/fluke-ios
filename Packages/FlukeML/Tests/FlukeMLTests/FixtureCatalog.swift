import CryptoKit
import Foundation
@testable import FlukeML

struct FixtureCatalog {
    static let dimension = 384
    static let modelSHA256 = String(repeating: "a", count: 64)
    static let compatibility = IdentifierArtifactCompatibility(
        modelID: "facebook/dinov2-small",
        modelRevision: "ed25f3a31f01632728cabb09d1542f84ab7b0056",
        modelVersion: "dinov2-small-coreml-v1",
        modelSHA256: modelSHA256,
        preprocessingVersion: "dinov2-imagenet-v1",
        indexVersion: "mobile-reference-v1"
    )

    let directory: URL

    init(
        metadata: [[String: Any]]? = nil,
        vectors: [[Float]]? = nil,
        manifestUpdates: [String: Any] = [:],
        metadataData: Data? = nil
    ) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let resolvedMetadata: [[String: Any]]
        if let metadata {
            resolvedMetadata = metadata
        } else {
            resolvedMetadata = try Self.defaultMetadata
        }
        let resolvedMetadataData: Data
        if let metadataData {
            resolvedMetadataData = metadataData
        } else {
            resolvedMetadataData = try Self.encodedJSON(resolvedMetadata)
        }
        let resolvedVectors = vectors ?? Self.defaultVectors
        let vectorData = Self.float16Data(resolvedVectors.flatMap { $0 })
        let manifest = Self.manifest(
            referenceCount: resolvedMetadata.count,
            catalogCount: Set(resolvedMetadata.compactMap { $0["catalogId"] as? String }).count,
            vectorsSHA256: Self.sha256(vectorData),
            metadataSHA256: Self.sha256(resolvedMetadataData),
            updates: manifestUpdates
        )

        try resolvedMetadataData.write(to: directory.appendingPathComponent("metadata.json"))
        try vectorData.write(to: directory.appendingPathComponent("references.f16"))
        try Self.encodedJSON(manifest).write(to: directory.appendingPathComponent("manifest.json"))
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    func makeBundle(appBuild: Int) throws -> Bundle {
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).bundle", isDirectory: true)
        let resourcesURL = bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
        try FileManager.default.createDirectory(
            at: resourcesURL,
            withIntermediateDirectories: true
        )
        let info: [String: Any] = [
            "CFBundleIdentifier": "test.orcawatch.FlukeMLFixtures",
            "CFBundlePackageType": "BNDL",
            "CFBundleVersion": String(appBuild),
        ]
        let infoData = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try infoData.write(
            to: bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Info.plist")
        )
        try FileManager.default.copyItem(
            at: directory,
            to: resourcesURL.appendingPathComponent("IdentifierCatalog", isDirectory: true)
        )
        guard let bundle = Bundle(url: bundleURL) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return bundle
    }

    static var queryEmbedding: [Float] {
        unitVector(score: 1)
    }

    static var defaultMetadata: [[String: Any]] {
        get throws {
            guard let url = Bundle.module.url(
                forResource: "producer-metadata",
                withExtension: "json"
            ) else {
                throw CocoaError(.fileNoSuchFile)
            }
            let data = try Data(contentsOf: url)
            guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return rows
        }
    }

    static let defaultVectors: [[Float]] = [
        unitVector(score: 1),
        unitVector(score: 0.98),
        unitVector(score: 0.96),
        unitVector(score: 0.10),
        unitVector(score: 0.90),
        unitVector(score: 0.88),
        unitVector(score: 0.80),
    ]

    static func unitVector(score: Float) -> [Float] {
        let second = sqrt(max(0, 1 - score * score))
        return [score, second] + [Float](repeating: 0, count: dimension - 2)
    }

    static func row(referenceID: String, whaleID: String, catalogID: String) -> [String: Any] {
        [
            "referencePhotoId": referenceID,
            "whaleId": whaleID,
            "catalogId": catalogID,
            "sourceId": "synthetic-owned-fixture",
        ]
    }

    static func encodedJSON(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func float16Data(_ values: [Float]) -> Data {
        values.reduce(into: Data()) { data, value in
            var bits = Float16(value).bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func manifest(
        referenceCount: Int,
        catalogCount: Int,
        vectorsSHA256: String,
        metadataSHA256: String,
        updates: [String: Any]
    ) -> [String: Any] {
        let base: [String: Any] = [
            "schemaVersion": 1,
            "manifestVersion": "2026-07-18",
            "modelId": compatibility.modelID,
            "modelRevision": compatibility.modelRevision,
            "modelVersion": compatibility.modelVersion,
            "modelSha256": compatibility.modelSHA256,
            "preprocessingVersion": compatibility.preprocessingVersion,
            "embeddingDimension": dimension,
            "dtype": "float16",
            "indexVersion": compatibility.indexVersion,
            "minimumAppBuild": 1,
            "maximumAppBuild": 100,
            "referenceCount": referenceCount,
            "catalogCount": catalogCount,
            "vectorsSha256": vectorsSHA256,
            "metadataSha256": metadataSHA256,
            "rightsAttestationSha256": String(repeating: "b", count: 64),
            "scoreSemantics": "uncalibrated_similarity_not_probability",
            "scoreThreshold": 0.72,
            "marginThreshold": 0.08,
        ]
        return base.merging(updates) { _, replacement in replacement }
    }
}
