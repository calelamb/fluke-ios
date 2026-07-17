import FlukeKit
import FlukeUI
import SwiftUI

public struct WhaleProfileView: View {
    @State private var viewModel: WhaleProfileViewModel
    @State private var isMovementPresented = false
    private let repository: any WhalesRepositoryProtocol
    private let openTrace: () -> Void
    private let openSubmit: () -> Void

    public init(
        whale: Whale,
        repository: any WhalesRepositoryProtocol,
        onOpenTrace: @escaping () -> Void = {},
        onOpenSubmit: @escaping () -> Void = {}
    ) {
        _viewModel = State(initialValue: WhaleProfileViewModel(whale: whale, repository: repository))
        self.repository = repository
        openTrace = onOpenTrace
        openSubmit = onOpenSubmit
    }

    public var body: some View {
        Group {
            if let profile = viewModel.profile {
                profileContent(profile)
            } else if viewModel.state.isLoading {
                ProgressView("Loading whale profile")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let failure = viewModel.state.failure {
                ContentUnavailableView {
                    Label("Profile unavailable", systemImage: "water.waves")
                } description: {
                    Text(failure.message)
                } actions: {
                    if failure.retryable {
                        Button("Retry") { Task { await viewModel.retry() } }
                    }
                }
            } else if viewModel.isEmpty {
                VStack(spacing: 12) {
                    if let notice = viewModel.state.notice {
                        noticeView(notice)
                    }
                    ContentUnavailableView(
                        "Profile not found",
                        systemImage: "questionmark.circle",
                        description: Text("No saved public profile is available for this whale.")
                    )
                }
            }
        }
        .background(Color.fog)
        .navigationTitle(viewModel.whale.catalogId)
        .task { await viewModel.load() }
        .movementCover(isPresented: $isMovementPresented) {
            MovementTrackView(
                repository: repository,
                whale: viewModel.whale,
                onSubmitSighting: openSubmit
            )
        }
    }

    private func profileContent(_ profile: WhaleProfile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let notice = viewModel.state.notice {
                    noticeView(notice)
                }
                identity(profile.whale)
                Button { isMovementPresented = true } label: {
                    Label("See movement", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(.tide)
                Button(action: openTrace) {
                    Label("Explore in Atlas", systemImage: "globe.americas")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                }
                .buttonStyle(.bordered)
                .tint(.deep)
                optionalTextSection("Biography", profile.whale.biography)
                optionalTextSection("Distinguishing marks", profile.whale.distinguishingMarks)
                family(profile)
                events(profile.whale.notableEvents)
                recentSightings(profile.recentSightings)
                citations(profile.whale.sourceCitations)
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(20)
        }
        .refreshable { await viewModel.retry() }
    }

    private func identity(_ whale: Whale) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(whale.name ?? "Unnamed whale")
                .font(.flukeDisplayMedium)
                .foregroundStyle(Color.abyss)
            Text([whale.catalogId, whale.pod.map { "Pod \($0)" }, whale.ecotype.flukeDisplayName]
                .compactMap { $0 }.joined(separator: " · "))
                .font(.flukeBody)
                .foregroundStyle(Color.deep)
            Text(WhaleProfilePresentation.lifeLabel(whale))
                .font(.flukeLabel)
                .foregroundStyle(Color.deep)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func optionalTextSection(_ title: String, _ value: String?) -> some View {
        if let value = normalized(value) {
            section(title) { Text(value).textSelection(.enabled) }
        }
    }

    @ViewBuilder
    private func family(_ profile: WhaleProfile) -> some View {
        if profile.mother != nil || !profile.offspring.isEmpty {
            section("Family") {
                if let mother = profile.mother {
                    relation("Mother", mother)
                }
                ForEach(profile.offspring, id: \.catalogId) { offspring in
                    relation("Offspring", offspring)
                }
            }
        }
    }

    private func relation(_ role: String, _ whale: WhaleRelation) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(role).font(.flukeLabel)
            Text([whale.catalogId, whale.name].compactMap { $0 }.joined(separator: " · "))
        }
    }

    @ViewBuilder
    private func events(_ values: [NotableEvent]) -> some View {
        if !values.isEmpty {
            section("Notable events") {
                ForEach(Array(values.enumerated()), id: \.offset) { _, event in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(event.year)).font(.flukeLabel)
                        Text(event.summary).textSelection(.enabled)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func recentSightings(_ values: [RecentSighting]) -> some View {
        if !values.isEmpty {
            section("Recent sightings") {
                ForEach(values) { sighting in
                    Text("\(sighting.observedAt.formatted(date: .abbreviated, time: .omitted)) · \(sighting.locationName ?? "Salish Sea")")
                }
            }
        }
    }

    @ViewBuilder
    private func citations(_ values: [SourceCitation]) -> some View {
        if !values.isEmpty {
            section("Sources") {
                ForEach(Array(values.enumerated()), id: \.offset) { _, citation in
                    if let url = URL(string: citation.url) {
                        Link(citation.label, destination: url)
                    }
                }
            }
        }
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.flukeDisplaySmall).foregroundStyle(Color.abyss)
            content().font(.flukeBody).foregroundStyle(Color.deep)
        }
    }

    private func noticeView(_ notice: BrowseNotice) -> some View {
        Group {
            switch notice {
            case .offline: BrowseStatusView(kind: .offline) { Task { await viewModel.retry() } }
            case .stale(let failure):
                BrowseStatusView(kind: .stale(failure)) { Task { await viewModel.retry() } }
            }
        }
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension View {
    @ViewBuilder
    fileprivate func movementCover<Destination: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        #if os(macOS)
        sheet(isPresented: isPresented, content: destination)
        #else
        fullScreenCover(isPresented: isPresented, content: destination)
        #endif
    }
}

enum WhaleProfilePresentation {
    static func lifeLabel(_ whale: Whale) -> String {
        let years = [whale.birthYear, whale.deathYear].compactMap { $0 }.map(String.init)
        let status = whale.status.rawValue.capitalized
        guard !years.isEmpty else { return status }
        return "\(years.joined(separator: "–")) · \(status)"
    }
}
