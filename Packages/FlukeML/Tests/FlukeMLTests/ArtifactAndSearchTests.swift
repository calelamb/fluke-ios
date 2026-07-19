import Foundation
import Testing
@testable import FlukeML

@Suite("Identifier artifact loading")
struct IdentifierArtifactLoadingTests {
    @Test("loads the exact producer schema and immutable catalog")
    func loadsProducerSchema() throws {
        let catalog = try ReferenceCatalog.load(
            directory: FixtureCatalog.producerCatalogDirectory,
            compatibility: FixtureCatalog.compatibility,
            appBuild: 42
        )

        #expect(catalog.manifest.schemaVersion == 1)
        #expect(catalog.manifest.embeddingDimension == 384)
        #expect(catalog.referenceCount == 7)
        #expect(catalog.catalogCount == 3)
        #expect(catalog.dimension == 384)
    }

    @Test("pins producer commit and exact generated artifact bytes")
    func producerFixtureProvenance() throws {
        let provenance = try FixtureCatalog.producerProvenance
        let artifacts = try #require(provenance["artifacts"] as? [String: String])
        let expectedNames = Set(["manifest.json", "metadata.json", "references.f16"])
        let directory = try FixtureCatalog.producerCatalogDirectory
        let actualNames = Set(
            try FileManager.default.contentsOfDirectory(atPath: directory.path)
        )

        #expect(
            provenance["producerCommit"] as? String
                == "7aa6474ca51c4c7e91cd4552093e7cc3424924b2"
        )
        #expect(actualNames == expectedNames)
        #expect(Set(artifacts.keys) == expectedNames)
        for name in expectedNames {
            let data = try Data(contentsOf: directory.appendingPathComponent(name))
            #expect(FixtureCatalog.sha256(data) == artifacts[name])
        }
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

    @Test("bundle loading rejects traversal outside its resource directory")
    func bundleTraversal() throws {
        let fixture = try FixtureCatalog()
        defer { fixture.remove() }
        let bundle = try fixture.makeBundle(appBuild: 42)
        defer { try? FileManager.default.removeItem(at: bundle.bundleURL) }
        let outsideCatalog = try #require(bundle.resourceURL?.deletingLastPathComponent())
            .appendingPathComponent("OutsideCatalog", isDirectory: true)
        try FileManager.default.copyItem(at: fixture.directory, to: outsideCatalog)

        #expect(throws: IdentifierArtifactError.invalidArtifactDirectory) {
            try ReferenceCatalog.load(
                bundle: bundle,
                compatibility: FixtureCatalog.compatibility,
                catalogDirectoryName: "../OutsideCatalog"
            )
        }
    }

    @Test("directory loading rejects a symlinked parent component")
    func symlinkedParent() throws {
        let fixture = try FixtureCatalog()
        defer { fixture.remove() }
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: container) }
        let realParent = container.appendingPathComponent("real", isDirectory: true)
        let linkedParent = container.appendingPathComponent("linked", isDirectory: true)
        let catalog = realParent.appendingPathComponent("catalog", isDirectory: true)
        try FileManager.default.createDirectory(at: realParent, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture.directory, to: catalog)
        try FileManager.default.createSymbolicLink(at: linkedParent, withDestinationURL: realParent)

        #expect(throws: IdentifierArtifactError.invalidArtifactDirectory) {
            try ReferenceCatalog.load(
                directory: linkedParent.appendingPathComponent("catalog", isDirectory: true),
                compatibility: FixtureCatalog.compatibility,
                appBuild: 42
            )
        }
    }

    @Test("catalog loading rejects symlinked artifact files")
    func symlinkedArtifact() throws {
        let fixture = try FixtureCatalog()
        defer { fixture.remove() }
        let vectorsURL = fixture.directory.appendingPathComponent("references.f16")
        let outsideURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).f16")
        defer { try? FileManager.default.removeItem(at: outsideURL) }
        try FileManager.default.moveItem(at: vectorsURL, to: outsideURL)
        try FileManager.default.createSymbolicLink(at: vectorsURL, withDestinationURL: outsideURL)

        #expect(throws: IdentifierArtifactError.unreadableArtifact("references.f16")) {
            try ReferenceCatalog.load(
                directory: fixture.directory,
                compatibility: FixtureCatalog.compatibility,
                appBuild: 42
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
            ("schemaVersion", "2"),
            ("embeddingDimension", "383"),
            ("dtype", "\"float32\""),
            ("scoreSemantics", "\"probability\""),
            ("scoreThreshold", "1.01"),
            ("marginThreshold", "-1.01"),
            ("vectorsSha256", "\"ABC\""),
            ("vectorsSha256", "\"\(String(repeating: "١", count: 32))\""),
        ]
    )
    func malformedManifest(field: String, rawValue: String) throws {
        let fixture = try FixtureCatalog()
        defer { fixture.remove() }
        try fixture.replaceManifestValue(field: field, with: rawValue)

        #expect(throws: IdentifierArtifactError.invalidManifest(field)) {
            try ReferenceCatalog.load(
                directory: fixture.directory,
                compatibility: FixtureCatalog.compatibility,
                appBuild: 42
            )
        }
    }

    @Test(
        "integer fields require integer JSON tokens",
        arguments: [
            ("schemaVersion", "1.0"),
            ("embeddingDimension", "3.84e2"),
            ("referenceCount", "7e0"),
            ("catalogCount", "3.0"),
            ("minimumAppBuild", "1e0"),
            ("maximumAppBuild", "100.0"),
        ]
    )
    func exactIntegerTokens(field: String, rawValue: String) throws {
        let fixture = try FixtureCatalog()
        defer { fixture.remove() }
        try fixture.replaceManifestValue(field: field, with: rawValue)

        #expect(throws: IdentifierArtifactError.invalidManifest(field)) {
            try ReferenceCatalog.load(
                directory: fixture.directory,
                compatibility: FixtureCatalog.compatibility,
                appBuild: 42
            )
        }
    }

    @Test(
        "numeric fields reject booleans",
        arguments: [
            "schemaVersion", "embeddingDimension", "referenceCount", "catalogCount",
            "minimumAppBuild", "maximumAppBuild", "scoreThreshold", "marginThreshold",
        ]
    )
    func numericBooleans(field: String) throws {
        let fixture = try FixtureCatalog()
        defer { fixture.remove() }
        try fixture.replaceManifestValue(field: field, with: "true")

        #expect(throws: IdentifierArtifactError.invalidManifest(field)) {
            try ReferenceCatalog.load(
                directory: fixture.directory,
                compatibility: FixtureCatalog.compatibility,
                appBuild: 42
            )
        }
    }

    @Test(
        "thresholds are bounded as Double before narrowing to Float",
        arguments: [
            ("scoreThreshold", "1.00000001"),
            ("marginThreshold", "-1.00000001"),
        ]
    )
    func doubleThresholdBounds(field: String, rawValue: String) throws {
        let fixture = try FixtureCatalog()
        defer { fixture.remove() }
        try fixture.replaceManifestValue(field: field, with: rawValue)

        #expect(throws: IdentifierArtifactError.invalidManifest(field)) {
            try ReferenceCatalog.load(
                directory: fixture.directory,
                compatibility: FixtureCatalog.compatibility,
                appBuild: 42
            )
        }
    }

    @Test("unrepresentable JSON numbers fail closed")
    func unrepresentableNumber() throws {
        let fixture = try FixtureCatalog()
        defer { fixture.remove() }
        try fixture.replaceManifestValue(field: "scoreThreshold", with: "1e400")

        #expect(throws: IdentifierArtifactError.self) {
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

    @Test("accepts producer-approved Float16 normalization drift")
    func float16NormalizationTolerance() throws {
        var vectors = FixtureCatalog.defaultVectors
        let quantizedUnit = Float(Float16(1.0015))
        vectors[0] = [quantizedUnit]
            + [Float](repeating: 0, count: FixtureCatalog.dimension - 1)
        let fixture = try FixtureCatalog(vectors: vectors)
        defer { fixture.remove() }

        _ = try ReferenceCatalog.load(
            directory: fixture.directory,
            compatibility: FixtureCatalog.compatibility,
            appBuild: 42
        )
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
        let catalog = try ReferenceCatalog.load(
            directory: FixtureCatalog.producerCatalogDirectory,
            compatibility: FixtureCatalog.compatibility,
            appBuild: 42
        )
        let searcher = ExactCosineSearcher(catalog: catalog)

        let results = try searcher.search(embedding: FixtureCatalog.queryEmbedding, limit: 3)
        let provenance = try FixtureCatalog.producerProvenance
        let golden = try #require(provenance["golden"] as? [String: Any])
        let identities = try #require(golden["identities"] as? [[String: Any]])
        let expectedCatalogIDs = identities.compactMap { $0["catalogId"] as? String }
        let expectedScores = identities.compactMap { ($0["score"] as? NSNumber)?.floatValue }
        let expectedReferences = identities.compactMap {
            $0["referencePhotoIds"] as? [String]
        }

        #expect(results.map(\.catalogID) == expectedCatalogIDs)
        #expect(results.map(\.rank) == [1, 2, 3])
        #expect(zip(results.map(\.score), expectedScores).allSatisfy { abs($0 - $1) < 0.000_001 })
        #expect(results.map(\.matchedReferencePhotoIDs) == expectedReferences)
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

    @Test("keeps source Float32 query normalization strict")
    func queryNormalizationTolerance() throws {
        let fixture = try FixtureCatalog()
        defer { fixture.remove() }
        let searcher = try makeSearcher(fixture)
        let embedding = [Float(1.0015)]
            + [Float](repeating: 0, count: FixtureCatalog.dimension - 1)

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
