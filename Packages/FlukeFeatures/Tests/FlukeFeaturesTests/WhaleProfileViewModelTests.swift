import FlukeKit
import Foundation
import Testing

@testable import FlukeFeatures

@MainActor
@Suite("Whale profile presentation")
struct WhaleProfileViewModelTests {
    private let metadata = BrowseMetadata(fetchedAt: Date(), schemaVersion: 1)

    @Test("Profile load uses the selected whale identity")
    func identity() async {
        let profile = makeProfile()
        let repository = WhalesRepositoryFake(profiles: [
            .fresh(value: profile, metadata: metadata),
        ])
        let model = WhaleProfileViewModel(whale: profile.whale, repository: repository)

        await model.load()

        #expect(model.profile == profile)
        #expect(await repository.profileIDs == [profile.whale.id])
    }

    @Test("A missing profile is a true empty state")
    func missingProfile() async {
        let whale = makeWhale(id: "missing", catalogId: "X1", name: nil, ecotype: .unknown, pod: nil)
        let repository = WhalesRepositoryFake(profiles: [.empty(metadata: metadata)])
        let model = WhaleProfileViewModel(whale: whale, repository: repository)

        await model.load()

        #expect(model.profile == nil)
        #expect(model.isEmpty)
    }

    @Test("An offline empty profile retains its offline notice")
    func offlineEmptyProfile() async {
        let whale = makeWhale(id: "missing", catalogId: "X1", name: nil, ecotype: .unknown, pod: nil)
        let repository = WhalesRepositoryFake(profiles: [
            .cachedOffline(payload: .empty, metadata: metadata)
        ])
        let model = WhaleProfileViewModel(whale: whale, repository: repository)

        await model.load()

        #expect(model.isEmpty)
        #expect(model.state.notice == .offline)
    }

    @Test("Offline profile remains visible and retry refreshes it")
    func offlineAndRetry() async {
        let profile = makeProfile()
        let repository = WhalesRepositoryFake(profiles: [
            .cachedOffline(payload: .value(profile), metadata: metadata),
            .fresh(value: profile, metadata: metadata),
        ])
        let model = WhaleProfileViewModel(whale: profile.whale, repository: repository)

        await model.load()
        #expect(model.profile == profile)
        #expect(model.state.notice == .offline)
        await model.retry()
        #expect(model.state.notice == nil)
        #expect(await repository.profileIDs.count == 2)
    }

    private func makeProfile() -> WhaleProfile {
        let whale = makeWhale(
            id: "whale-j35", catalogId: "J35", name: "Tahlequah",
            ecotype: .resident, pod: "J"
        )
        return WhaleProfile(whale: whale, mother: nil, offspring: [], recentSightings: [])
    }
}

@Suite("Whale profile presentation copy")
struct WhaleProfilePresentationTests {
    @Test("Missing life years leave only the known status")
    func missingYearsDoNotInventPlaceholderCopy() {
        let whale = Whale(
            id: "whale-x1", catalogId: "X1", name: nil, ecotype: .unknown,
            pod: nil, sex: .unknown, birthYear: nil, deathYear: nil, status: .alive,
            biography: nil, distinguishingMarks: nil, heroImageUrl: nil,
            notableEvents: [], sourceCitations: []
        )

        let label = WhaleProfilePresentation.lifeLabel(whale)

        #expect(label == "Alive")
        #expect(!label.localizedCaseInsensitiveContains("unknown"))
    }
}
