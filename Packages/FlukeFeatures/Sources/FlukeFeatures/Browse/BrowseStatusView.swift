import FlukeKit
import FlukeUI
import SwiftUI

public struct BrowseStatusView: View {
    public enum Kind: Equatable {
        case offline
        case stale(BrowseFailure)
        case failure(BrowseFailure)
    }

    private let kind: Kind
    private let retry: (() -> Void)?

    public init(kind: Kind, retry: (() -> Void)? = nil) {
        self.kind = kind
        self.retry = retry
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
            Text(message)
                .font(.flukeBody)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let retry, canRetry {
                Button("Retry", action: retry)
                    .font(.flukeBody.weight(.semibold))
                    .frame(minHeight: 44)
            }
        }
        .foregroundStyle(Color.abyss)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(backgroundColor)
    }

    private var message: String {
        switch kind {
        case .offline: "Showing saved data while you are offline."
        case .stale(let failure), .failure(let failure): failure.message
        }
    }

    private var systemImage: String {
        switch kind {
        case .offline: "wifi.slash"
        case .stale: "arrow.clockwise"
        case .failure: "exclamationmark.triangle"
        }
    }

    private var backgroundColor: Color {
        switch kind {
        case .failure: Color.ember.opacity(0.16)
        case .offline, .stale: Color.fog
        }
    }

    private var canRetry: Bool {
        switch kind {
        case .offline: true
        case .stale(let failure), .failure(let failure): failure.retryable
        }
    }
}
