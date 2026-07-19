import CryptoKit
import CoreFoundation
import Foundation

public struct ReferenceCatalog: Sendable {
    static let maximumJSONBytes = 16 * 1_024 * 1_024
    static let maximumReferenceCount = 50_000
    static let expectedDimension = 384

    public let manifest: IdentifierArtifactManifest
    public let referenceCount: Int
    public let catalogCount: Int
    public let dimension: Int

    let vectors: [Float]
    let records: [ReferenceRecord]

    private init(
        manifest: IdentifierArtifactManifest,
        vectors: [Float],
        records: [ReferenceRecord]
    ) {
        self.manifest = manifest
        referenceCount = manifest.referenceCount
        catalogCount = manifest.catalogCount
        dimension = manifest.embeddingDimension
        self.vectors = vectors
        self.records = records
    }

    public static func load(
        bundle: Bundle,
        compatibility: IdentifierArtifactCompatibility,
        catalogDirectoryName: String = "IdentifierCatalog"
    ) throws -> ReferenceCatalog {
        guard
            let rawBuild = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
            let appBuild = Int(rawBuild),
            appBuild > 0,
            let resourceURL = bundle.resourceURL
        else {
            throw IdentifierArtifactError.invalidAppBuild
        }
        return try CatalogArtifactReader.withSubdirectory(
            parent: resourceURL,
            name: catalogDirectoryName
        ) { descriptor in
            try load(
                directoryDescriptor: descriptor,
                compatibility: compatibility,
                appBuild: appBuild
            )
        }
    }

    public static func load(
        directory: URL,
        compatibility: IdentifierArtifactCompatibility,
        appBuild: Int
    ) throws -> ReferenceCatalog {
        guard appBuild > 0 else { throw IdentifierArtifactError.invalidAppBuild }
        return try CatalogArtifactReader.withDirectory(at: directory) { descriptor in
            try load(
                directoryDescriptor: descriptor,
                compatibility: compatibility,
                appBuild: appBuild
            )
        }
    }

    private static func load(
        directoryDescriptor: Int32,
        compatibility: IdentifierArtifactCompatibility,
        appBuild: Int
    ) throws -> ReferenceCatalog {
        let manifestData = try readJSON(named: "manifest.json", from: directoryDescriptor)
        let manifest = try decodeManifest(manifestData)
        try validate(manifest: manifest, compatibility: compatibility, appBuild: appBuild)

        let metadataData = try readJSON(named: "metadata.json", from: directoryDescriptor)
        let records = try decodeMetadata(metadataData)
        try requireDigest(
            metadataData,
            expected: manifest.metadataSHA256,
            artifactName: "metadata.json"
        )

        let vectorData = try readVectors(from: directoryDescriptor, manifest: manifest)
        let vectors = try decodeVectors(vectorData, manifest: manifest)
        try validateMetadata(records, manifest: manifest)

        return ReferenceCatalog(manifest: manifest, vectors: vectors, records: records)
    }

    func validateQuery(_ embedding: [Float]) throws {
        guard embedding.count == dimension, embedding.allSatisfy(\.isFinite) else {
            throw IdentifierArtifactError.invalidQuery
        }
        guard Self.isNormalized(embedding, tolerance: Self.sourceNormTolerance) else {
            throw IdentifierArtifactError.invalidQuery
        }
    }
}

struct ReferenceRecord: Equatable, Sendable {
    let referencePhotoID: String
    let whaleID: String
    let catalogID: String
    let sourceID: String
}

private extension ReferenceCatalog {
    static let metadataKeys = Set(["referencePhotoId", "whaleId", "catalogId", "sourceId"])
    static let scoreSemantics = "uncalibrated_similarity_not_probability"
    static let float16ByteCount = 2
    static let sourceNormTolerance: Float = 0.001
    static let float16NormTolerance: Float = 0.002
    static let integerManifestFields = [
        "schemaVersion", "embeddingDimension", "minimumAppBuild", "maximumAppBuild",
        "referenceCount", "catalogCount",
    ]
    static let thresholdManifestFields = ["scoreThreshold", "marginThreshold"]

    static func readJSON(named name: String, from directoryDescriptor: Int32) throws -> Data {
        let data = try CatalogArtifactReader.readJSON(
            named: name,
            from: directoryDescriptor,
            maximumBytes: maximumJSONBytes
        )
        guard String(data: data, encoding: .utf8) != nil else {
            throw IdentifierArtifactError.invalidJSON(name)
        }
        return data
    }

    static func decodeManifest(_ data: Data) throws -> IdentifierArtifactManifest {
        guard
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            Set(payload.keys) == IdentifierArtifactManifest.expectedKeys,
            try validateRawNumbers(payload),
            let manifest = try? JSONDecoder().decode(IdentifierArtifactManifest.self, from: data)
        else {
            throw IdentifierArtifactError.invalidManifestSchema
        }
        return manifest
    }

    static func validateRawNumbers(_ payload: [String: Any]) throws -> Bool {
        for field in integerManifestFields {
            guard let number = payload[field] as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(),
                  !CFNumberIsFloatType(number) else {
                throw IdentifierArtifactError.invalidManifest(field)
            }
        }
        for field in thresholdManifestFields {
            guard let number = payload[field] as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite,
                  (-1.0 ... 1.0).contains(number.doubleValue) else {
                throw IdentifierArtifactError.invalidManifest(field)
            }
        }
        return true
    }

    static func validate(
        manifest: IdentifierArtifactManifest,
        compatibility: IdentifierArtifactCompatibility,
        appBuild: Int
    ) throws {
        try validateManifestScalars(manifest)
        guard (manifest.minimumAppBuild ... manifest.maximumAppBuild).contains(appBuild) else {
            throw IdentifierArtifactError.appBuildOutOfRange
        }
        let pairs = compatibilityPairs(manifest: manifest, compatibility: compatibility)
        if let mismatch = pairs.first(where: { $0.actual != $0.expected }) {
            throw IdentifierArtifactError.incompatibleArtifact(mismatch.name)
        }
    }

    static func validateManifestScalars(_ value: IdentifierArtifactManifest) throws {
        try require(value.schemaVersion == 1, field: "schemaVersion")
        try require(!value.manifestVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    field: "manifestVersion")
        try require(value.embeddingDimension == expectedDimension, field: "embeddingDimension")
        try require(value.dtype == "float16", field: "dtype")
        try require((1 ... maximumReferenceCount).contains(value.referenceCount),
                    field: "referenceCount")
        try require((1 ... value.referenceCount).contains(value.catalogCount), field: "catalogCount")
        try require(value.minimumAppBuild > 0, field: "minimumAppBuild")
        try require(value.maximumAppBuild >= value.minimumAppBuild, field: "maximumAppBuild")
        try validateTextAndHashes(value)
        try require(value.scoreSemantics == scoreSemantics, field: "scoreSemantics")
        try require(validThreshold(value.scoreThreshold), field: "scoreThreshold")
        try require(validThreshold(value.marginThreshold), field: "marginThreshold")
    }

    static func validateTextAndHashes(_ value: IdentifierArtifactManifest) throws {
        let texts = [
            (value.modelID, "modelID"),
            (value.modelRevision, "modelRevision"),
            (value.modelVersion, "modelVersion"),
            (value.preprocessingVersion, "preprocessingVersion"),
            (value.indexVersion, "indexVersion"),
        ]
        if let invalid = texts.first(where: {
            $0.0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) {
            throw IdentifierArtifactError.invalidManifest(invalid.1)
        }
        let hashes = [
            (value.modelSHA256, "modelSha256"),
            (value.vectorsSHA256, "vectorsSha256"),
            (value.metadataSHA256, "metadataSha256"),
            (value.rightsAttestationSHA256, "rightsAttestationSha256"),
        ]
        if let invalid = hashes.first(where: { !validSHA256($0.0) }) {
            throw IdentifierArtifactError.invalidManifest(invalid.1)
        }
    }

    static func compatibilityPairs(
        manifest: IdentifierArtifactManifest,
        compatibility: IdentifierArtifactCompatibility
    ) -> [(actual: String, expected: String, name: String)] {
        [
            (manifest.modelID, compatibility.modelID, "modelID"),
            (manifest.modelRevision, compatibility.modelRevision, "revision"),
            (manifest.modelVersion, compatibility.modelVersion, "version"),
            (manifest.modelSHA256, compatibility.modelSHA256, "sha"),
            (manifest.preprocessingVersion, compatibility.preprocessingVersion, "preprocessing"),
            (manifest.indexVersion, compatibility.indexVersion, "index"),
        ]
    }

    static func require(_ condition: Bool, field: String) throws {
        guard condition else { throw IdentifierArtifactError.invalidManifest(field) }
    }

    static func validThreshold(_ value: Float) -> Bool {
        value.isFinite && (-1 ... 1).contains(value)
    }

    static func validSHA256(_ value: String) -> Bool {
        let characters = Set("0123456789abcdef")
        return value.count == 64 && value.allSatisfy(characters.contains)
    }

    static func decodeMetadata(_ data: Data) throws -> [ReferenceRecord] {
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              !payload.isEmpty else {
            throw IdentifierArtifactError.invalidMetadataSchema
        }
        return try payload.map { row in
            guard Set(row.keys) == metadataKeys,
                  let referenceID = nonemptyString(row["referencePhotoId"]),
                  let whaleID = nonemptyString(row["whaleId"]),
                  let catalogID = nonemptyString(row["catalogId"]),
                  let sourceID = nonemptyString(row["sourceId"]) else {
                throw IdentifierArtifactError.invalidMetadataSchema
            }
            return ReferenceRecord(
                referencePhotoID: referenceID,
                whaleID: whaleID,
                catalogID: catalogID,
                sourceID: sourceID
            )
        }
    }

    static func nonemptyString(_ value: Any?) -> String? {
        guard let value = value as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }

    static func validateMetadata(
        _ records: [ReferenceRecord],
        manifest: IdentifierArtifactManifest
    ) throws {
        guard records.count == manifest.referenceCount,
              Set(records.map(\.catalogID)).count == manifest.catalogCount else {
            throw IdentifierArtifactError.invalidMetadataCount
        }
        let referenceIDs = records.map(\.referencePhotoID)
        guard Set(referenceIDs).count == referenceIDs.count,
              referenceIDs == referenceIDs.sorted() else {
            throw IdentifierArtifactError.invalidIdentityMetadata
        }
        guard stableIdentityMapping(records) else {
            throw IdentifierArtifactError.invalidIdentityMetadata
        }
    }

    static func stableIdentityMapping(_ records: [ReferenceRecord]) -> Bool {
        let whales = Dictionary(grouping: records, by: \.whaleID)
        let catalogs = Dictionary(grouping: records, by: \.catalogID)
        return whales.values.allSatisfy { Set($0.map(\.catalogID)).count == 1 }
            && catalogs.values.allSatisfy { Set($0.map(\.whaleID)).count == 1 }
    }

    static func readVectors(
        from directoryDescriptor: Int32,
        manifest: IdentifierArtifactManifest
    ) throws -> Data {
        let expected = try expectedVectorBytes(manifest)
        let data = try CatalogArtifactReader.readExact(
            named: "references.f16",
            from: directoryDescriptor,
            byteCount: expected
        )
        guard SHA256.hash(data: data).hexDigest == manifest.vectorsSHA256 else {
            throw IdentifierArtifactError.digestMismatch("references.f16")
        }
        return data
    }

    static func expectedVectorBytes(_ manifest: IdentifierArtifactManifest) throws -> Int {
        let (elements, overflow) = manifest.referenceCount.multipliedReportingOverflow(
            by: manifest.embeddingDimension
        )
        let (bytes, byteOverflow) = elements.multipliedReportingOverflow(by: float16ByteCount)
        guard !overflow, !byteOverflow else {
            throw IdentifierArtifactError.invalidVectorLength
        }
        return bytes
    }

    static func decodeVectors(
        _ data: Data,
        manifest: IdentifierArtifactManifest
    ) throws -> [Float] {
        let values = stride(from: 0, to: data.count, by: float16ByteCount).map { offset in
            let bits = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            return Float(Float16(bitPattern: bits))
        }
        guard values.allSatisfy(\.isFinite) else {
            throw IdentifierArtifactError.invalidVectors
        }
        for row in 0 ..< manifest.referenceCount {
            let start = row * manifest.embeddingDimension
            let end = start + manifest.embeddingDimension
            guard isNormalized(
                values[start ..< end],
                tolerance: float16NormTolerance
            ) else {
                throw IdentifierArtifactError.invalidVectors
            }
        }
        return values
    }

    static func isNormalized<C: Collection>(
        _ values: C,
        tolerance: Float
    ) -> Bool where C.Element == Float {
        let sum = values.reduce(Float.zero) { $0 + $1 * $1 }
        return sum.isFinite && abs(sqrt(sum) - 1) <= tolerance
    }

    static func requireDigest(
        _ data: Data,
        expected: String,
        artifactName: String
    ) throws {
        guard SHA256.hash(data: data).hexDigest == expected else {
            throw IdentifierArtifactError.digestMismatch(artifactName)
        }
    }

}

private extension Digest {
    var hexDigest: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
