import FlukeKit
import Foundation
import Testing

@testable import FlukeFeatures

@Suite("Browse presentation state")
struct BrowseViewStateTests {
    private let metadata = BrowseMetadata(
        fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
        schemaVersion: 1
    )
    private let retryableFailure = BrowseFailure(
        code: "OFFLINE",
        message: "Connect to the internet and try again.",
        retryable: true,
        requestId: nil
    )

    @Test("Fresh and empty results map without notices")
    func freshAndEmpty() {
        #expect(
            BrowseViewState<[Int]>.resolve(.fresh(value: [1, 2], metadata: metadata))
                == .content([1, 2], notice: nil, isRefreshing: false)
        )
        #expect(
            BrowseViewState<[Int]>.resolve(.empty(metadata: metadata))
                == .empty(notice: nil, isRefreshing: false)
        )
    }

    @Test("Stale results retain cached values and safe failure copy")
    func stale() {
        #expect(
            BrowseViewState<[Int]>.resolve(.stale(
                payload: .value([3]),
                metadata: metadata,
                failure: retryableFailure
            )) == .content(
                [3],
                notice: .stale(retryableFailure),
                isRefreshing: false
            )
        )
        #expect(
            BrowseViewState<[Int]>.resolve(.stale(
                payload: .empty,
                metadata: metadata,
                failure: retryableFailure
            )) == .empty(
                notice: .stale(retryableFailure),
                isRefreshing: false
            )
        )
    }

    @Test("Offline results retain cached values and empty truth")
    func offline() {
        #expect(
            BrowseViewState<[Int]>.resolve(.cachedOffline(
                payload: .value([4]),
                metadata: metadata
            )) == .content([4], notice: .offline, isRefreshing: false)
        )
        #expect(
            BrowseViewState<[Int]>.resolve(.cachedOffline(
                payload: .empty,
                metadata: metadata
            )) == .empty(notice: .offline, isRefreshing: false)
        )
    }

    @Test("Failure maps without inventing content")
    func failure() {
        #expect(
            BrowseViewState<[Int]>.resolve(.failed(retryableFailure))
                == .failed(retryableFailure)
        )
    }

    @Test("Refresh preserves known content and notices")
    func refreshPreservesTruth() {
        #expect(
            BrowseViewState<[Int]>.content(
                [5],
                notice: .offline,
                isRefreshing: false
            ).beginRefresh() == .content(
                [5],
                notice: .offline,
                isRefreshing: true
            )
        )
        #expect(
            BrowseViewState<[Int]>.empty(
                notice: nil,
                isRefreshing: false
            ).beginRefresh() == .empty(
                notice: nil,
                isRefreshing: true
            )
        )
        #expect(BrowseViewState<[Int]>.idle.beginRefresh() == .loading)
        #expect(BrowseViewState<[Int]>.failed(retryableFailure).beginRefresh() == .loading)
    }
}
