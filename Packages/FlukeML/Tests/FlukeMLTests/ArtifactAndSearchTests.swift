import Foundation
import Testing
@testable import FlukeML

@Suite("Identifier artifact loading")
struct IdentifierArtifactLoadingTests {
    @Test("loads the exact producer schema and immutable catalog")
    func loadsProducerSchema() throws {
        let fixture = try FixtureCatalog()
        defer { fixture.remove() }

        let catalog = try ReferenceCatalog.load(
            directory: fixture.directory,
            compatibility: FixtureCatalog.compatibility,
            appBuild: 42
        )

        #expect(catalog.manifest.schemaVersion == 1)
        #expect(catalog.manifest.embeddingDimension == 384)
        #expect(catalog.referenceCount == 7)
        #expect(catalog.catalogCount == 3)
        #expect(catalog.dimension == 384)
    }

    @Test("bundle loading derives and enforces the running app build")
    func bundleLoadingUsesRunningBuild() throws {
        let fixture = try FixtureCatalog()
        defer { fixture.remove() }
        let compatibleBundle = try fixture.makeBundle(appBuild: 42)
        defer { try? FileManager.default.removeItem(at: compatibleBundle.bundleURL) }

        let catalog = try ReferenceCatalog.load(
            bundle: compatibleBundle,
            compatibility: FixtureCatalog.compatibility
        )
        #expect(catalog.referenceCount == 7)

        let incompatibleBundle = try fixture.makeBundle(appBuild: 101)
        defer { try? FileManager.default.removeItem(at: incompatibleBundle.bundleURL) }
        #expect(throws: IdentifierArtifactError.appBuildOutOfRange) {
            try ReferenceCatalog.load(
                bundle: incompatibleBundle,
                compatibility: FixtureCatalog.compatibility
            )
        }
    }

    @Test("rejects a vector digest mismatch atomically")
    func digestMismatch() throws {
        let fixture = try FixtureCatalog()
        defer { fixture.remove() }
        let vectorsURL = fixture.directory.appendingPathComponent("references.f16")
        var bytes = try Data(contentsOf: vectorsURL)
        bytes[0] ^= 0x01
        try bytes.write(to: vectorsURL)

        #expect(throws: IdentifierArtifactError.digestMismatch("references.f16")) {
            try ReferenceCatalog.load(
                directory: fixture.directory,
                compatibility: FixtureCatalog.compatibility,
                appBuild: 42
            )
        }
    }

    @Test(
        "rejects missing and unknown manifest fields",
        arguments: ["remove", "add"]
    )
    func exactManifestSchema(mutation: String) throws {
        let fixture = try FixtureCatalog()
        defer { fixture.remove() }
        let url = fixture.directory.appendingPathComponent("manifest.json")
        var payload = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        if mutation == "remove" {
            payload.removeValue(forKey: "modelVersion")
        } else {
            payload["unknownField"] = true
        }
        try FixtureCatalog.encodedJSON(payload).write(to: url)

        #expect(throws: IdentifierArtifactError.invalidManifestSchema) {
            try ReferenceCatalog.load(
                directory: fixture.directory,
                compatibility: FixtureCatalog.compatibility,
                appBuild: 42
            )
        }
    }

    @Test("rejects unknown metadata fields before constructing catalog state")
    func exactMetadataSchema() throws {
        var rows = try FixtureCatalog.defaultMetadata
        rows[0]["unknownField"] = "drift"
        let fixture = try FixtureCatalog(metadata: rows)
        defer { fixture.remove() }

        #expect(throws: IdentifierArtifactError.invalidMetadataSchema) {
            try ReferenceCatalog.load(
                directory: fixture.directory,
                compatibility: FixtureCatalog.compatibility,
                appBuild: 42
            )
        }
    }

    @Test(
        "rejects malformed manifest scalar contracts",
        arguments: [
            ("schemaVersion", 2 as Any),
            ("embeddingDimension", 383 as Any),
            ("dtype", "float32" as Any),
            ("scoreSemantics", "probability" as Any),
            ("scoreThreshold", 1.01 as Any),
            ("marginThreshold", -1.01 as Any),
            ("vectorsSha256", "ABC" as Any),
            ("vectorsSha256", String(repeating: "١", count: 32) as Any),
        ]
    )
    func malformedManifest(field: String, value: Any) throws {
        let fixture = try FixtureCatalog(manifestUpdates: [field: value])
        defer { fixture.remove() }

        #expect(throws: IdentifierArtifactError.invalidManifest(field)) {
            try ReferenceCatalog.load(
                directory: fixture.directory,
                compatibility: FixtureCatalog.compatibility,
                appBuild: 42
            )
        }
    }

    @Test(
        "requires positive ordered bounds containing the app build",
        arguments: [
            (["minimumAppBuild": 0], 1),
            (["minimumAppBuild": 10, "maximumAppBuild": 9], 10),
            (["minimumAppBuild": 5, "maximumAppBuild": 9], 4),
            (["minimumAppBuild": 5, "maximumAppBuild": 9], 10),
        ]
    )
    func appBuildBounds(updates: [String: Int], appBuild: Int) throws {
        let fixture = try FixtureCatalog(manifestUpdates: updates)
        defer { fixture.remove() }

        #expect(throws: IdentifierArtifactError.self) {
            try ReferenceCatalog.load(
                directory: fixture.directory,
                compatibility: FixtureCatalog.compatibility,
                appBuild: appBuild
            )
        }
    }

    @Test("rejects a non-positive injected app build")
    func invalidInjectedAppBuild() throws {
        let fixture = try FixtureCatalog()
        defer { fixture.remove() }

        #expect(throws: IdentifierArtifactError.invalidAppBuild) {
            try ReferenceCatalog.load(
                directory: fixture.directory,
                compatibility: FixtureCatalog.compatibility,
                appBuild: 0
            )
        }
    }

    @Test(
        "requires exact model and index compatibility",
        arguments: ["modelID", "revision", "version", "sha", "preprocessing", "index"]
    )
    func compatibility(field: String) throws {
        let fixture = try FixtureCatalog()
        defer { fixture.remove() }
        let baseline = FixtureCatalog.compatibility
        let compatibility = IdentifierArtifactCompatibility(
            modelID: field == "modelID" ? "wrong" : baseline.modelID,
            modelRevision: field == "revision" ? "wrong" : baseline.modelRevision,
            modelVersion: field == "version" ? "wrong" : baseline.modelVersion,
            modelSHA256: field == "sha" ? String(repeating: "c", count: 64) : baseline.modelSHA256,
            preprocessingVersion: field == "preprocessing" ? "wrong" : baseline.preprocessingVersion,
            indexVersion: field == "index" ? "wrong" : baseline.indexVersion
        )

        #expect(throws: IdentifierArtifactError.incompatibleArtifact(field)) {
            try ReferenceCatalog.load(
                directory: fixture.directory,
                compatibility: compatibility,
                appBuild: 42
            )
        }
    }

    @Test("rejects invalid Float16 byte length")
    func vectorLength() throws {
        let fixture = try FixtureCatalog(vectors: Array(FixtureCatalog.defaultVectors.dropLast()))
        defer { fixture.remove() }

        #expect(throws: IdentifierArtifactError.invalidVectorLength) {
            try ReferenceCatalog.load(
                directory: fixture.directory,
                compatibility: FixtureCatalog.compatibility,
                appBuild: 42
            )
        }
    }

    @Test(
        "rejects non-finite and non-normalized vectors",
        arguments: [Float.nan, Float(0.5)]
    )
    func invalidVectors(firstValue: Float) throws {
        var vectors = FixtureCatalog.defaultVectors
        vectors[0] = [firstValue] + [Float](repeating: 0, count: FixtureCatalog.dimension - 1)
        let fixture = try FixtureCatalog(vectors: vectors)
        defer { fixture.remove() }

        #expect(throws: IdentifierArtifactError.invalidVectors) {
            try ReferenceCatalog.load(
                directory: fixture.directory,
                compatibility: FixtureCatalog.compatibility,
                appBuild: 42
            )
        }
    }

    @Test(
        "rejects duplicate, unstable, or unsorted stable IDs",
        arguments: ["duplicate", "whale", "catalog", "unsorted"]
    )
    func identityValidation(mutation: String) throws {
        var rows = try FixtureCatalog.defaultMetadata
        switch mutation {
        case "duplicate":
            rows[1]["referencePhotoId"] = rows[0]["referencePhotoId"]
        case "whale":
            rows[1]["catalogId"] = "J27"
        case "catalog":
            rows[4]["catalogId"] = "J35"
        default:
            rows.swapAt(0, 1)
        }
        let fixture = try FixtureCatalog(metadata: rows)
        defer { fixture.remove() }

        #expect(throws: IdentifierArtifactError.invalidIdentityMetadata) {
            try ReferenceCatalog.load(
                directory: fixture.directory,
                compatibility: FixtureCatalog.compatibility,
                appBuild: 42
            )
        }
    }

    @Test("rejects metadata and catalog counts that do not agree")
    func countValidation() throws {
        let fixture = try FixtureCatalog(manifestUpdates: ["catalogCount": 4])
        defer { fixture.remove() }

        #expect(throws: IdentifierArtifactError.invalidMetadataCount) {
            try ReferenceCatalog.load(
                directory: fixture.directory,
                compatibility: FixtureCatalog.compatibility,
                appBuild: 42
            )
        }
    }

    @Test("rejects invalid UTF-8 and oversized JSON")
    func boundedUTF8JSON() throws {
        let invalidFixture = try FixtureCatalog()
        defer { invalidFixture.remove() }
        try Data([0xFF]).write(
            to: invalidFixture.directory.appendingPathComponent("metadata.json")
        )
        #expect(throws: IdentifierArtifactError.invalidJSON("metadata.json")) {
            try ReferenceCatalog.load(
                directory: invalidFixture.directory,
                compatibility: FixtureCatalog.compatibility,
                appBuild: 42
            )
        }

        let oversizedFixture = try FixtureCatalog()
        defer { oversizedFixture.remove() }
        try Data(repeating: 0x20, count: ReferenceCatalog.maximumJSONBytes + 1).write(
            to: oversizedFixture.directory.appendingPathComponent("metadata.json")
        )
        #expect(throws: IdentifierArtifactError.artifactTooLarge("metadata.json")) {
            try ReferenceCatalog.load(
                directory: oversizedFixture.directory,
                compatibility: FixtureCatalog.compatibility,
                appBuild: 42
            )
        }
    }
}

@Suite("Exact cosine search")
struct ExactCosineSearchTests {
    @Test("returns the producer-fixture golden identity order")
    func goldenOrder() throws {
        let fixture = try FixtureCatalog()
        defer { fixture.remove() }
        let searcher = try makeSearcher(fixture)

        let results = try searcher.search(embedding: FixtureCatalog.queryEmbedding, limit: 3)

        #expect(results.map(\.catalogID) == ["J35", "J27", "T049A"])
        #expect(results.map(\.rank) == [1, 2, 3])
        #expect(abs(results[0].score - 0.98) < 0.002)
        #expect(results[0].matchedReferencePhotoIDs == ["ref-001", "ref-002", "ref-003"])
    }

    @Test("aggregates mean top three after the global top 25 references")
    func globalTop25ThenTopThree() throws {
        let aRows = [
            FixtureCatalog.row(referenceID: "ref-a1", whaleID: "whale-a", catalogID: "A"),
            FixtureCatalog.row(referenceID: "ref-a2", whaleID: "whale-a", catalogID: "A"),
            FixtureCatalog.row(referenceID: "ref-a3", whaleID: "whale-a", catalogID: "A"),
        ]
        let bRows = (1 ... 25).map {
            FixtureCatalog.row(
                referenceID: String(format: "ref-b%02d", $0),
                whaleID: "whale-b",
                catalogID: "B"
            )
        }
        let vectors = [
            FixtureCatalog.unitVector(score: 0.9),
            FixtureCatalog.unitVector(score: 0.8),
            FixtureCatalog.unitVector(score: -1),
        ] + [
            [Float]
        ](repeating: FixtureCatalog.unitVector(score: 0.7), count: 25)
        let fixture = try FixtureCatalog(metadata: aRows + bRows, vectors: vectors)
        defer { fixture.remove() }

        let results = try makeSearcher(fixture).search(
            embedding: FixtureCatalog.queryEmbedding,
            limit: 2
        )

        #expect(results.map(\.catalogID) == ["A", "B"])
        #expect(abs(results[0].score - 0.85) < 0.002)
        #expect(results[0].matchedReferencePhotoIDs == ["ref-a1", "ref-a2"])
    }

    @Test("breaks score ties deterministically by stable identity")
    func deterministicTies() throws {
        let rows = [
            FixtureCatalog.row(referenceID: "ref-z", whaleID: "whale-z", catalogID: "Z"),
            FixtureCatalog.row(referenceID: "ref-a", whaleID: "whale-a", catalogID: "A"),
        ].sorted {
            ($0["referencePhotoId"] as? String ?? "") < ($1["referencePhotoId"] as? String ?? "")
        }
        let vectors = [[Float]](
            repeating: FixtureCatalog.unitVector(score: 0.8),
            count: 2
        )
        let fixture = try FixtureCatalog(metadata: rows, vectors: vectors)
        defer { fixture.remove() }

        let results = try makeSearcher(fixture).search(
            embedding: FixtureCatalog.queryEmbedding,
            limit: 2
        )

        #expect(results.map(\.catalogID) == ["A", "Z"])
    }

    @Test(
        "rejects malformed queries",
        arguments: ["dimension", "nan", "norm"]
    )
    func invalidQuery(mutation: String) throws {
        let fixture = try FixtureCatalog()
        defer { fixture.remove() }
        let searcher = try makeSearcher(fixture)
        let embedding: [Float]
        switch mutation {
        case "dimension":
            embedding = [Float](repeating: 0, count: 383)
        case "nan":
            embedding = [.nan] + [Float](repeating: 0, count: 383)
        default:
            embedding = [Float](repeating: 0, count: 384)
        }

        #expect(throws: IdentifierArtifactError.invalidQuery) {
            try searcher.search(embedding: embedding, limit: 3)
        }
    }

    @Test("rejects unbounded result limits", arguments: [0, 101])
    func invalidLimit(limit: Int) throws {
        let fixture = try FixtureCatalog()
        defer { fixture.remove() }
        let searcher = try makeSearcher(fixture)

        #expect(throws: IdentifierArtifactError.invalidLimit) {
            try searcher.search(embedding: FixtureCatalog.queryEmbedding, limit: limit)
        }
    }

    @Test("caps results at the available identity count")
    func capsResults() throws {
        let fixture = try FixtureCatalog()
        defer { fixture.remove() }
        let results = try makeSearcher(fixture).search(
            embedding: FixtureCatalog.queryEmbedding,
            limit: 100
        )

        #expect(results.count == 3)
    }

    private func makeSearcher(_ fixture: FixtureCatalog) throws -> ExactCosineSearcher {
        let catalog = try ReferenceCatalog.load(
            directory: fixture.directory,
            compatibility: FixtureCatalog.compatibility,
            appBuild: 42
        )
        return ExactCosineSearcher(catalog: catalog)
    }
}
