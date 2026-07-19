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
}

extension IdentifierArtifactManifest {
    static let expectedKeys = Set(CodingKeys.allCases.map(\.rawValue))
}

extension IdentifierArtifactManifest.CodingKeys: CaseIterable {}
