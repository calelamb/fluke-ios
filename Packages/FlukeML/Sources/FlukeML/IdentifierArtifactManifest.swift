import Foundation

public struct IdentifierArtifactManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let manifestVersion: String
    public let modelID: String
    public let modelRevision: String
    public let modelVersion: String
    public let modelSHA256: String
    public let preprocessingVersion: String
    public let embeddingDimension: Int
    public let dtype: String
    public let indexVersion: String
    public let minimumAppBuild: Int
    public let maximumAppBuild: Int
    public let referenceCount: Int
    public let catalogCount: Int
    public let vectorsSHA256: String
    public let metadataSHA256: String
    public let rightsAttestationSHA256: String
    public let scoreSemantics: String
    public let scoreThreshold: Float
    public let marginThreshold: Float

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case manifestVersion
        case modelID = "modelId"
        case modelRevision
        case modelVersion
        case modelSHA256 = "modelSha256"
        case preprocessingVersion
        case embeddingDimension
        case dtype
        case indexVersion
        case minimumAppBuild
        case maximumAppBuild
        case referenceCount
        case catalogCount
        case vectorsSHA256 = "vectorsSha256"
        case metadataSHA256 = "metadataSha256"
        case rightsAttestationSHA256 = "rightsAttestationSha256"
        case scoreSemantics
        case scoreThreshold
        case marginThreshold
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        manifestVersion = try values.decode(String.self, forKey: .manifestVersion)
        modelID = try values.decode(String.self, forKey: .modelID)
        modelRevision = try values.decode(String.self, forKey: .modelRevision)
        modelVersion = try values.decode(String.self, forKey: .modelVersion)
        modelSHA256 = try values.decode(String.self, forKey: .modelSHA256)
        preprocessingVersion = try values.decode(String.self, forKey: .preprocessingVersion)
        embeddingDimension = try values.decode(Int.self, forKey: .embeddingDimension)
        dtype = try values.decode(String.self, forKey: .dtype)
        indexVersion = try values.decode(String.self, forKey: .indexVersion)
        minimumAppBuild = try values.decode(Int.self, forKey: .minimumAppBuild)
        maximumAppBuild = try values.decode(Int.self, forKey: .maximumAppBuild)
        referenceCount = try values.decode(Int.self, forKey: .referenceCount)
        catalogCount = try values.decode(Int.self, forKey: .catalogCount)
        vectorsSHA256 = try values.decode(String.self, forKey: .vectorsSHA256)
        metadataSHA256 = try values.decode(String.self, forKey: .metadataSHA256)
        rightsAttestationSHA256 = try values.decode(String.self, forKey: .rightsAttestationSHA256)
        scoreSemantics = try values.decode(String.self, forKey: .scoreSemantics)
        scoreThreshold = try Self.decodeThreshold(from: values, forKey: .scoreThreshold)
        marginThreshold = try Self.decodeThreshold(from: values, forKey: .marginThreshold)
    }

    private static func decodeThreshold(
        from values: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Float {
        let value = try values.decode(Double.self, forKey: key)
        guard value.isFinite, (-1.0 ... 1.0).contains(value) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: values,
                debugDescription: "Threshold must be finite and within [-1, 1]."
            )
        }
        return Float(value)
    }
}

extension IdentifierArtifactManifest {
    static let expectedKeys = Set(CodingKeys.allCases.map(\.rawValue))
}

extension IdentifierArtifactManifest.CodingKeys: CaseIterable {}
