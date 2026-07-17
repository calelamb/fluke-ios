import FlukeKit

public enum BrowseNotice: Equatable, Sendable {
    case stale(BrowseFailure)
    case offline
}

public enum BrowseViewState<Value: Codable & Equatable & Sendable>: Equatable, Sendable {
    case idle
    case loading
    case content(Value, notice: BrowseNotice?, isRefreshing: Bool)
    case empty(notice: BrowseNotice?, isRefreshing: Bool)
    case failed(BrowseFailure)

    public static func resolve(_ result: BrowseResult<Value>) -> Self {
        switch result {
        case .fresh(let value, _):
            return .content(value, notice: nil, isRefreshing: false)
        case .empty:
            return .empty(notice: nil, isRefreshing: false)
        case .stale(let payload, _, let failure):
            return resolve(payload, notice: .stale(failure))
        case .cachedOffline(let payload, _):
            return resolve(payload, notice: .offline)
        case .failed(let failure):
            return .failed(failure)
        }
    }

    public func beginRefresh() -> Self {
        switch self {
        case .content(let value, let notice, _):
            return .content(value, notice: notice, isRefreshing: true)
        case .empty(let notice, _):
            return .empty(notice: notice, isRefreshing: true)
        case .idle, .loading, .failed:
            return .loading
        }
    }

    public var value: Value? {
        guard case .content(let value, _, _) = self else { return nil }
        return value
    }

    public var notice: BrowseNotice? {
        switch self {
        case .content(_, let notice, _), .empty(let notice, _): notice
        case .idle, .loading, .failed: nil
        }
    }

    public var failure: BrowseFailure? {
        guard case .failed(let failure) = self else { return nil }
        return failure
    }

    public var isLoading: Bool {
        switch self {
        case .loading: true
        case .content(_, _, let isRefreshing), .empty(_, let isRefreshing): isRefreshing
        case .idle, .failed: false
        }
    }

    private static func resolve(_ payload: BrowsePayload<Value>, notice: BrowseNotice) -> Self {
        switch payload {
        case .value(let value): .content(value, notice: notice, isRefreshing: false)
        case .empty: .empty(notice: notice, isRefreshing: false)
        }
    }
}

extension BrowseFailure {
    static let unexpectedFeatureFailure = BrowseFailure(
        code: "REQUEST_FAILED",
        message: "Fluke couldn't complete the request.",
        retryable: true,
        requestId: nil
    )
}
