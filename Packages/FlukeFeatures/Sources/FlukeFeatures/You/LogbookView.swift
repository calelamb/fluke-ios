import FlukeReleaseB
import FlukeUI
import SwiftUI

extension LogbookStatus {
  public var title: String {
    switch self {
    case .queued: "Queued"
    case .pending: "Pending"
    case .approved: "Approved"
    case .rejected: "Rejected"
    }
  }

  public var explanation: String {
    switch self {
    case .queued: "Saved on this device and waiting to upload."
    case .pending: "Received and waiting for moderator review."
    case .approved: "Approved for the public sightings record."
    case .rejected: "Reviewed and not published to the public record."
    }
  }
}

public struct LogbookView: View {
  @State private var viewModel: LogbookViewModel
  private let onSessionExpired: () -> Void
  private let invalidationObserver: any SubmissionInvalidationObserving

  public init(
    repository: any LogbookRepositoryProtocol,
    queue: any QueuedLogbookProviding,
    invalidationObserver: any SubmissionInvalidationObserving =
      NoopSubmissionInvalidationObserver(),
    onSessionExpired: @escaping () -> Void
  ) {
    _viewModel = State(initialValue: LogbookViewModel(repository: repository, queue: queue))
    self.onSessionExpired = onSessionExpired
    self.invalidationObserver = invalidationObserver
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      statusGuide
      if let failure = viewModel.failure {
        errorCard(failure)
      }
      if viewModel.rows.isEmpty, !viewModel.isLoading {
        ContentUnavailableView(
          "No sightings yet",
          systemImage: "book.closed",
          description: Text("Submitted sightings and their review status will appear here.")
        )
      } else {
        rows
      }
    }
    .task { await viewModel.observeInvalidations(from: invalidationObserver) }
    .refreshable { await load() }
    .onChange(of: viewModel.sessionAction) { _, action in
      if action == .expire { onSessionExpired() }
    }
  }

  private var statusGuide: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Status guide")
        .font(.flukeDisplaySmall)
        .foregroundStyle(Color.abyss)
      ForEach(LogbookStatus.allCases, id: \.self) { status in
        HStack(alignment: .top, spacing: 8) {
          Circle()
            .fill(color(for: status))
            .frame(width: 8, height: 8)
            .padding(.top, 5)
            .accessibilityHidden(true)
          Text("\(status.title): \(status.explanation)")
            .font(.flukeBody)
            .foregroundStyle(Color.deep)
        }
      }
    }
    .padding(16)
    .background(Color.bone, in: RoundedRectangle(cornerRadius: 14))
  }

  private var rows: some View {
    LazyVStack(spacing: 10) {
      ForEach(viewModel.rows) { row in
        HStack(alignment: .top, spacing: 12) {
          VStack(alignment: .leading, spacing: 5) {
            Text(row.locationName ?? "Location not provided")
              .font(.flukeDisplaySmall)
              .foregroundStyle(Color.abyss)
            Text(row.observedAt.formatted(date: .abbreviated, time: .shortened))
              .font(.flukeBody)
              .foregroundStyle(Color.deep)
          }
          Spacer(minLength: 8)
          Text(row.status.title)
            .font(.flukeLabel)
            .foregroundStyle(Color.abyss)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(color(for: row.status).opacity(0.18), in: Capsule())
        }
        .padding(16)
        .background(Color.bone, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
      }
    }
  }

  private func errorCard(_ failure: LogbookFailure) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Logbook unavailable")
        .font(.flukeDisplaySmall)
      Text(failure.message)
        .font(.flukeBody)
      if failure.retryable {
        Button("Retry") { Task { await load() } }
          .buttonStyle(.borderedProminent)
          .tint(Color.tide)
          .youMinimumHitTarget(.retry)
      }
    }
    .foregroundStyle(Color.abyss)
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.ember.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
  }

  private func load() async {
    await viewModel.load()
    if viewModel.sessionAction == .expire { onSessionExpired() }
  }

  private func color(for status: LogbookStatus) -> Color {
    switch status {
    case .queued: Color.swell
    case .pending: Color.ember
    case .approved: Color.tide
    case .rejected: Color.deep
    }
  }
}
