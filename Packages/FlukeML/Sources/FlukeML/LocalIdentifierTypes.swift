import Foundation

public enum IdentifierArtifactError: Error, Equatable, LocalizedError, Sendable {
    case invalidArtifactDirectory
    case missingArtifact(String)
    case unreadableArtifact(String)
    case artifactTooLarge(String)
    case invalidJSON(String)
    case invalidManifestSchema
    case invalidManifest(String)
    case invalidMetadataSchema
    case invalidMetadataCount
    case invalidIdentityMetadata
    case invalidVectorLength
    case invalidVectors
    case digestMismatch(String)
    case invalidAppBuild
    case appBuildOutOfRange
    case incompatibleArtifact(String)
    case invalidQuery
    case invalidLimit

    public var errorDescription: String? {
        switch self {
        case .invalidArtifactDirectory:
            return "The local identifier catalog directory is invalid."
        case .missingArtifact(let name):
            return "The local identifier artifact is missing: \(name)."
        case .unreadableArtifact(let name):
            return "The local identifier artifact cannot be read: \(name)."
        case .artifactTooLarge(let name):
            return "The local identifier artifact exceeds its size limit: \(name)."
        case .invalidJSON(let name):
            return "The local identifier artifact is not valid UTF-8 JSON: \(name)."
        case .invalidManifestSchema, .invalidManifest:
            return "The local identifier manifest is invalid."
        case .invalidMetadataSchema, .invalidMetadataCount, .invalidIdentityMetadata:
            return "The local identifier metadata is invalid."
        case .invalidVectorLength, .invalidVectors:
            return "The local identifier vectors are invalid."
        case .digestMismatch(let name):
            return "The local identifier artifact failed integrity validation: \(name)."
        case .invalidAppBuild, .appBuildOutOfRange:
            return "This local identifier catalog is not compatible with this app build."
        case .incompatibleArtifact:
            return "The local identifier catalog does not match the embedded model."
        case .invalidQuery:
            return "The local identifier query embedding is invalid."
        case .invalidLimit:
            return "The local identifier result limit is invalid."
        }
    }
}

public struct IdentifierArtifactCompatibility: Equatable, Sendable {
    public let modelID: String
    public let modelRevision: String
    public let modelVersion: String
    public let modelSHA256: String
    public let preprocessingVersion: String
    public let indexVersion: String

    public init(
        modelID: String,
        modelRevision: String,
        modelVersion: String,
        modelSHA256: String,
        preprocessingVersion: String,
        indexVersion: String
    ) {
        self.modelID = modelID
        self.modelRevision = modelRevision
        self.modelVersion = modelVersion
        self.modelSHA256 = modelSHA256
        self.preprocessingVersion = preprocessingVersion
        self.indexVersion = indexVersion
    }
}

public struct LocalMatch: Equatable, Sendable {
    public let catalogID: String
    public let whaleID: String
    public let score: Float
    public let rank: Int
    public let matchedReferencePhotoIDs: [String]

    public init(
        catalogID: String,
        whaleID: String,
        score: Float,
        rank: Int,
        matchedReferencePhotoIDs: [String]
    ) {
        self.catalogID = catalogID
        self.whaleID = whaleID
        self.score = score
        self.rank = rank
        self.matchedReferencePhotoIDs = matchedReferencePhotoIDs
    }
}
