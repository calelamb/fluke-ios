import Accelerate
import Foundation

public struct ExactCosineSearcher: Sendable {
    static let maximumResultLimit = 100
    static let referenceLimit = 25
    static let aggregateReferenceLimit = 3

    private let catalog: ReferenceCatalog

    public init(catalog: ReferenceCatalog) {
        self.catalog = catalog
    }

    public func search(embedding: [Float], limit: Int) throws -> [LocalMatch] {
        guard (1 ... Self.maximumResultLimit).contains(limit) else {
            throw IdentifierArtifactError.invalidLimit
        }
        try catalog.validateQuery(embedding)
        let scores = multiply(embedding: embedding)
        return aggregate(scores: scores, identityLimit: limit)
    }
}

private extension ExactCosineSearcher {
    struct ScoredReference {
        let record: ReferenceRecord
        let score: Float
    }

    struct AggregatedIdentity {
        let catalogID: String
        let whaleID: String
        let score: Float
        let referencePhotoIDs: [String]
    }

    func multiply(embedding: [Float]) -> [Float] {
        var scores = [Float](repeating: 0, count: catalog.referenceCount)
        catalog.vectors.withUnsafeBufferPointer { matrix in
            embedding.withUnsafeBufferPointer { query in
                scores.withUnsafeMutableBufferPointer { output in
                    cblas_sgemv(
                        CblasRowMajor,
                        CblasNoTrans,
                        catalog.referenceCount,
                        catalog.dimension,
                        1,
                        matrix.baseAddress,
                        catalog.dimension,
                        query.baseAddress,
                        1,
                        0,
                        output.baseAddress,
                        1
                    )
                }
            }
        }
        return scores
    }

    func aggregate(scores: [Float], identityLimit: Int) -> [LocalMatch] {
        let references = zip(catalog.records, scores).map(ScoredReference.init)
        let topReferences = references.sorted(by: referenceRanksBefore).prefix(Self.referenceLimit)
        let grouped = Dictionary(grouping: topReferences, by: { $0.record.catalogID })
        let identities = grouped.values.map(aggregateIdentity).sorted(by: identityRanksBefore)
        return identities.prefix(identityLimit).enumerated().map { offset, identity in
            LocalMatch(
                catalogID: identity.catalogID,
                whaleID: identity.whaleID,
                score: identity.score,
                rank: offset + 1,
                matchedReferencePhotoIDs: identity.referencePhotoIDs
            )
        }
    }

    func aggregateIdentity(_ references: [ScoredReference]) -> AggregatedIdentity {
        let best = references.sorted(by: referenceRanksBefore)
            .prefix(Self.aggregateReferenceLimit)
        let score = best.reduce(Float.zero) { $0 + $1.score } / Float(best.count)
        let first = best[best.startIndex].record
        return AggregatedIdentity(
            catalogID: first.catalogID,
            whaleID: first.whaleID,
            score: score,
            referencePhotoIDs: best.map { $0.record.referencePhotoID }
        )
    }

    func referenceRanksBefore(_ lhs: ScoredReference, _ rhs: ScoredReference) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        return lhs.record.referencePhotoID < rhs.record.referencePhotoID
    }

    func identityRanksBefore(_ lhs: AggregatedIdentity, _ rhs: AggregatedIdentity) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.catalogID != rhs.catalogID { return lhs.catalogID < rhs.catalogID }
        return lhs.whaleID < rhs.whaleID
    }
}
