# Native Release A Browse Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace every shipping placeholder with accessible, resilient native browsing across Sightings, Whales, Learn, and Atlas.

**Architecture:** Feature-owned `@Observable` view models consume existing FlukeKit repository protocols and map `BrowseResult` into a shared immutable presentation state. Small SwiftUI views render content and status independently so valid cached content survives refresh, stale, and offline transitions.

**Tech Stack:** Swift 5.10 language mode, SwiftUI, Observation, Swift Testing, FlukeKit repository/cache protocols, FlukeUI tokens, iOS 17+.

## Global Constraints

- Release A exposes exactly Sightings, Whales, Learn, and Atlas.
- Do not import or route accounts, submissions, identification, or `FlukeReleaseB` from the app or FlukeFeatures.
- Use only local geometry, SF Symbols, the bundled Fraunces font, and API-provided HTTP(S) images.
- Preserve cached content across stale/offline/retry states and use safe server failure copy only.
- Support Dynamic Type, VoiceOver, Reduce Motion, contrast, 44-point controls, and keyboard search.
- Use no decorative emoji.

---

### Task 1: Shared resilient presentation state

**Files:**
- Create: `Packages/FlukeFeatures/Sources/FlukeFeatures/Browse/BrowseViewState.swift`
- Create: `Packages/FlukeFeatures/Sources/FlukeFeatures/Browse/BrowseStatusView.swift`
- Create: `Packages/FlukeFeatures/Tests/FlukeFeaturesTests/BrowseViewStateTests.swift`

**Interfaces:**
- Produces: `BrowseViewState<Value>`, `BrowseNotice`, `BrowseStatusView`, and immutable `beginRefresh()`/`resolve(_:)` transitions.

- [ ] **Step 1: Write failing state-mapping tests**

Test fresh, empty, stale value, stale empty, cached-offline value, cached-offline empty, failed, and refresh-preserves-content transitions. The desired interface is:

```swift
enum BrowseViewState<Value: Codable & Equatable & Sendable>: Equatable {
    case idle
    case loading
    case content(Value, notice: BrowseNotice?, isRefreshing: Bool)
    case empty(notice: BrowseNotice?, isRefreshing: Bool)
    case failed(BrowseFailure)

    func beginRefresh() -> Self
    static func resolve(_ result: BrowseResult<Value>) -> Self
}
```

- [ ] **Step 2: Verify RED**

Run `swift test --package-path Packages/FlukeFeatures --filter BrowseViewStateTests`; expect missing-type compilation failure.

- [ ] **Step 3: Implement minimal mapping and status UI**

`BrowseNotice` has `.stale(BrowseFailure)` and `.offline`. `BrowseStatusView` renders safe copy, Retry only when appropriate, and combines text with an SF Symbol plus explicit accessibility label.

- [ ] **Step 4: Verify GREEN**

Run the filtered test, then the full FlukeFeatures suite.

### Task 2: Sightings list, map, detail, and resilient model

**Files:**
- Delete: `Packages/FlukeFeatures/Sources/FlukeFeatures/Sightings/SightingsPlaceholder.swift`
- Create: `Packages/FlukeFeatures/Sources/FlukeFeatures/Sightings/SightingsViewModel.swift`
- Create: `Packages/FlukeFeatures/Sources/FlukeFeatures/Sightings/SightingsView.swift`
- Create: `Packages/FlukeFeatures/Sources/FlukeFeatures/Sightings/SightingsMapView.swift`
- Create: `Packages/FlukeFeatures/Sources/FlukeFeatures/Sightings/SightingDetailView.swift`
- Create: `Packages/FlukeFeatures/Tests/FlukeFeaturesTests/SightingsViewModelTests.swift`

**Interfaces:**
- Consumes: `any SightingsRepositoryProtocol`, `BrowseViewState`.
- Produces: `SightingsView(repository:)`, `SightingsViewModel.DisplayItem`, list/map selection, async `load()` and `retry()`.

- [ ] **Step 1: Write failing view-model tests**

Use an actor repository fake. Prove approved and external feeds merge newest-first, source identity is preserved, stale/offline content remains present, empty and failed states differ, Retry calls both feeds again, and an older delayed request cannot overwrite a newer response.

```swift
@MainActor
let model = SightingsViewModel(repository: fake)
await model.load()
#expect(model.items.map(\.id) == ["approved:new", "external:older"])
```

- [ ] **Step 2: Verify RED**

Run `swift test --package-path Packages/FlukeFeatures --filter SightingsViewModelTests`; expect missing-type failure.

- [ ] **Step 3: Implement model and views**

Use `LocalizedStringResource`-safe static copy, `ContentUnavailableView` for true empty/failed states, `.refreshable`, a large accessible List/Map picker, local `BasemapView`, projected markers, and one detail sheet shared by row and marker selection. Group each row into one VoiceOver element with date, location, source, ecotype, and group facts.

- [ ] **Step 4: Verify GREEN and render**

Run the filtered suite and add one render-smoke assertion that constructs List and Map modes with a deterministic fake repository.

### Task 3: Whale catalog and profile

**Files:**
- Delete: `Packages/FlukeFeatures/Sources/FlukeFeatures/Whales/WhalesPlaceholder.swift`
- Create: `Packages/FlukeFeatures/Sources/FlukeFeatures/Whales/WhalesViewModel.swift`
- Create: `Packages/FlukeFeatures/Sources/FlukeFeatures/Whales/WhalesView.swift`
- Create: `Packages/FlukeFeatures/Sources/FlukeFeatures/Whales/WhaleCard.swift`
- Create: `Packages/FlukeFeatures/Sources/FlukeFeatures/Whales/WhaleProfileViewModel.swift`
- Create: `Packages/FlukeFeatures/Sources/FlukeFeatures/Whales/WhaleProfileView.swift`
- Create: `Packages/FlukeFeatures/Tests/FlukeFeaturesTests/WhalesViewModelTests.swift`
- Create: `Packages/FlukeFeatures/Tests/FlukeFeaturesTests/WhaleProfileViewModelTests.swift`

**Interfaces:**
- Consumes: `any WhalesRepositoryProtocol`.
- Produces: `WhalesView(repository:onOpenTrace:)`, catalog `Filter`, deterministic `filteredWhales`, and profile `load()`/`retry()`.

- [ ] **Step 1: Write failing catalog/profile tests**

Prove localized search across catalog ID/name/pod/ecotype, every ecotype filter, stable alphabetical catalog ordering, stale/offline retention, missing-profile empty state, retry, and profile identity passed to the repository.

- [ ] **Step 2: Verify RED**

Run the two filtered test types; expect missing-type failure.

- [ ] **Step 3: Implement catalog and profile**

Use `.searchable`, horizontally scrollable filter controls, adaptive `LazyVGrid`, `AsyncImage` with textual fallback, and semantic profile sections. Render only present optional sections. Source citations open validated links. The trace action calls the injected read-only closure and never exposes submission UI.

- [ ] **Step 4: Verify GREEN and render**

Run filtered and full feature tests; instantiate catalog and profile surfaces in render smoke tests.

### Task 4: Rights-clear Learn reader

**Files:**
- Delete: `Packages/FlukeFeatures/Sources/FlukeFeatures/Learn/LearnPlaceholder.swift`
- Create: `Packages/FlukeFeatures/Sources/FlukeFeatures/Learn/LearnContent.swift`
- Create: `Packages/FlukeFeatures/Sources/FlukeFeatures/Learn/LearnView.swift`
- Create: `Packages/FlukeFeatures/Tests/FlukeFeaturesTests/LearnContentTests.swift`

**Interfaces:**
- Produces: immutable `LearnArticle` values and `LearnView()`.

- [ ] **Step 1: Write failing content tests**

Assert stable unique article IDs, nonempty headings/body/source labels, only HTTPS links, and no account/submission/identification claims.

- [ ] **Step 2: Verify RED**

Run `swift test --package-path Packages/FlukeFeatures --filter LearnContentTests`; expect missing-type failure.

- [ ] **Step 3: Implement reader**

Add local articles covering ecotypes, reading a sighting, responsible viewing, catalog evidence, cache freshness, and sources. Use semantic headings, selectable body text, readable width, and an attribution section.

- [ ] **Step 4: Verify GREEN**

Run the filtered suite and render smoke.

### Task 5: Resilient Atlas and real catalog

**Files:**
- Modify: `Packages/FlukeFeatures/Sources/FlukeFeatures/Atlas/AtlasView.swift`
- Modify: `Packages/FlukeFeatures/Sources/FlukeFeatures/Atlas/AtlasViewModel.swift`
- Modify: `Packages/FlukeFeatures/Sources/FlukeFeatures/Atlas/Timeline/TimelineViewModel.swift`
- Modify: `Packages/FlukeFeatures/Sources/FlukeFeatures/Atlas/Timeline/TimelineSubView.swift`
- Modify: `Packages/FlukeFeatures/Sources/FlukeFeatures/Atlas/Range/RangeViewModel.swift`
- Modify: `Packages/FlukeFeatures/Sources/FlukeFeatures/Atlas/Range/RangeSubView.swift`
- Modify: `Packages/FlukeFeatures/Sources/FlukeFeatures/Atlas/Trace/TraceViewModel.swift`
- Modify: `Packages/FlukeFeatures/Sources/FlukeFeatures/Atlas/Trace/TraceSubView.swift`
- Modify: `Packages/FlukeFeatures/Sources/FlukeFeatures/Atlas/Predict/PredictViewModel.swift`
- Modify: `Packages/FlukeFeatures/Sources/FlukeFeatures/Atlas/Predict/PredictSubView.swift`
- Create: `Packages/FlukeFeatures/Tests/FlukeFeaturesTests/AtlasBrowseViewModelTests.swift`

**Interfaces:**
- Consumes: all four public repository protocols and `BrowseViewState`.
- Produces: resilient Timeline, Range, Trace, Predict states and an Atlas-owned real whale catalog.

- [ ] **Step 1: Write failing Atlas state tests**

Prove each model calls `load` rather than live-only `fetch`, maps stale/offline/failed outcomes, retains cached content, handles sparse tracks, retries, and stops filtering/animation from erasing state. Prove the Atlas catalog loads real whales.

- [ ] **Step 2: Verify RED**

Run `swift test --package-path Packages/FlukeFeatures --filter AtlasBrowseViewModelTests`; expect initializer/state failures.

- [ ] **Step 3: Refactor Atlas**

Depend on protocol existentials, render shared status and retry controls, add accessibility labels/selected traits to every mode and filter control, use scroll containers at large text sizes, and disable polyline animation when Reduce Motion is enabled. Keep sparse trace copy read-only.

- [ ] **Step 4: Verify GREEN**

Run Atlas filtered tests, full feature tests, and FlukeUI snapshots.

### Task 6: Wire four-tab shell and harden boundary checks

**Files:**
- Modify: `App/Fluke/RootScene.swift`
- Modify: `App/FlukeTests/ReleaseAShellTests.swift`
- Delete: `Packages/FlukeFeatures/Sources/FlukeFeatures/Identify/IdentifyPlaceholder.swift`
- Delete: `Packages/FlukeFeatures/Sources/FlukeFeatures/You/YouPlaceholder.swift`
- Delete: `Packages/FlukeUI/Sources/FlukeUI/Components/PlaceholderScreen.swift`
- Modify: `scripts/verify-release-a-boundaries.sh`
- Modify: `scripts/tests/verification-scripts-tests.sh`
- Modify: `README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/testing.md`

**Interfaces:**
- Root constructs `SightingsView`, `WhalesView`, `LearnView`, and `AtlasView` with production repositories.

- [ ] **Step 1: Write failing shell and verifier tests**

Add assertions that all four real view type names are wired, no `PlaceholderScreen` or `*Placeholder` remains in shipping package sources, obsolete Identify/You source folders fail verification, and mutation/auth routes continue to fail.

- [ ] **Step 2: Verify RED**

Run the script self-test and pinned `ReleaseAShellTests`; expect placeholder-boundary failures.

- [ ] **Step 3: Wire and document**

Replace placeholder tabs with real views, remove obsolete sources, keep the exact tab enum, and update docs to describe native Release A behavior and external submission blockers.

- [ ] **Step 4: Verify GREEN**

Run script self-tests and pinned app tests.

### Task 7: Final verification, review, and local commit

**Files:** all changed files from Tasks 1–6.

- [ ] **Step 1: Run complete verification**

```bash
swift test --package-path Packages/FlukeKit --enable-code-coverage
swift test --package-path Packages/FlukeUI
swift test --package-path Packages/FlukeFeatures
scripts/verify-contract-fixtures.sh --api-root ../fluke-api
bash scripts/tests/verification-scripts-tests.sh
FLUKE_TEST_DESTINATION='platform=iOS Simulator,id=83AC73BB-03AB-46BB-98E3-6ACFCD32E8B7' scripts/verify-release-a-boundaries.sh
xcodebuild build -quiet -project App/Fluke.xcodeproj -scheme Fluke -configuration Release -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

- [ ] **Step 2: Review**

Run `git diff --check`, secret scanning, stale placeholder/Release B scans, file-size checks, and inspect all changed views for Dynamic Type, VoiceOver, Reduce Motion, safe links, immutable state, and explicit errors. Fix every Critical or High issue and rerun affected gates.

- [ ] **Step 3: Commit locally**

Stage only the reviewed UI slice and commit with `feat: ship native release a browse ui`. Do not push.
