# Contributing

How work gets done on Fluke iOS — the workflow, conventions, and review expectations.

## TL;DR

1. **Find the next task** in the active milestone plan at [`../../fluke/docs/plans/m-ios-N-*.md`](../../fluke/docs/plans/).
2. **Write the failing test first**, then minimal code to pass, then refactor.
3. **Commit with a conventional message** — `feat(scope): summary` / `fix(scope): summary` / `test(scope): summary`.
4. **Two-stage review** — spec compliance first, then code quality.
5. **Push** — CI runs all package tests + Xcode app tests.

## The active workflow: subagent-driven

This codebase is built using the [`superpowers:subagent-driven-development`](https://github.com/anthropics/superpowers) workflow. Each task in a milestone plan is dispatched to a fresh subagent with the task's full text + minimal scene-setting context. The subagent:

1. Implements the task following strict TDD.
2. Self-reviews before reporting back.
3. Reports `DONE` / `DONE_WITH_CONCERNS` / `BLOCKED` / `NEEDS_CONTEXT`.

After the implementer reports, two reviewers (or one combined) verify:

- **Spec compliance** — does the code match what the plan asked for? (Read files, run tests, diff against spec — don't trust the implementer's report.)
- **Code quality** — is it clean, focused, maintainable?

Failed reviews go back to the implementer (same subagent) for fixes; reviews re-run until both approve. Only then does the task get marked complete and the next one starts.

### Why this matters for human contributors

Plans are written assuming subagent execution: exact file paths, complete code blocks, test commands with expected output. A human picking up a task gets the same level of detail and can follow the same flow.

If you're a human contributor:

1. Read the task fully before starting. The plan is specific.
2. Write the failing test first (TDD red phase).
3. Implement minimum code to pass (TDD green phase).
4. Run the test command from the plan and confirm the expected output.
5. Commit with the suggested message.
6. Self-review against the plan's "Done definition".

## Project conventions

### TDD is non-negotiable

Every plan task that adds executable code starts with "Step 1: Write the failing test." This isn't aesthetic — it's a calibration check. If you write the test and it doesn't fail, your test is wrong. If you write the implementation and the test still fails, your implementation is wrong. Both surface bugs early.

The minimum coverage target is 80% (per the project's [`rules/common/testing.md`](https://github.com/calelamb/.claude/rules)). Snapshot tests count toward coverage of view code; logic tests cover services and view models.

Some tasks in the plan skip TDD (config-only changes, asset additions). Those are the exception, not the default.

### Commits are atomic and conventional

| Type | When | Example |
| --- | --- | --- |
| `feat` | New user-facing capability | `feat(features): add SightingsView with map+list+detail sheet` |
| `feat(kit)` | New domain capability | `feat(kit): add APIClient with cookie auth + typed errors` |
| `feat(ui)` | New design-system primitive | `feat(ui): add MapMarker with optional pulse animation` |
| `fix` | Bug fix | `fix(features): handle missing ecotype in WhaleProfile` |
| `test` | Tests only | `test(kit): cover APIError equality edge cases` |
| `chore` | Tooling, deps | `chore: bump swift-snapshot-testing to 1.18` |
| `docs` | Documentation only | `docs: clarify package boundary in architecture.md` |
| `ci` | CI workflow | `ci: matrix-test all 3 packages on macos-15` |

**One commit per task** when the task is small. **Multiple commits within a task** when there are clear sub-stages (test commit, implementation commit). Never bundle unrelated changes.

### File size budget

- Source files: aim for **200-400 lines**, hard cap **800**.
- Test files: same target.
- A file growing beyond the budget is a signal that it's doing too much. Split by responsibility, not by mechanical chunking.

### Naming

| Surface | Convention | Example |
| --- | --- | --- |
| Types | UpperCamelCase | `WhaleProfileViewModel` |
| Members | lowerCamelCase | `loadState`, `selected` |
| Booleans | `is`/`has`/`should` prefix | `isOnline`, `hasPhotos` |
| Asynchronous methods | `async throws` | `func fetchAll() async throws -> [Whale]` |
| Test names | `test_<behavior>` | `test_get_throwsUnauthorizedOn401` |

### Concurrency

- **`actor`** for repositories and services that hold mutable state across awaits.
- **`@MainActor` `@Observable`** for view models.
- **Avoid completion handlers** — use `async throws`. Wrap a system completion-handler API in `withCheckedThrowingContinuation` if needed.
- **`Sendable`** conformance on DTOs (`Whale`, `Sighting`, `IdentifyMatch`) is mandatory.

### Error handling

- Public APIs throw [`APIError`](../Packages/FlukeKit/Sources/FlukeKit/API/APIError.swift) for HTTP/parsing failures.
- View models translate `APIError` → user-facing strings via `.errorDescription`.
- Never silently swallow errors. The catch block at minimum logs to `print` (in dev) or surfaces to the user.

### Immutability

`let` over `var` whenever possible. DTOs are stored properties, all `let`. View model state is `@Published` private(set) where the view model mutates via methods. Direct mutation by views is the wrong shape.

## Adding a new feature

This is the canonical "I want to add a new screen" walkthrough.

### 1. Plan first

Don't open Xcode and start typing. Either:

- Pick the next task in the active milestone plan.
- Or, if you're starting a NEW milestone, create the plan first (see [`../../fluke/docs/plans/README.md`](../../fluke/docs/plans/) for the format).

The plan is the source of truth. The code follows.

### 2. Land the data layer first

If your screen needs new server data:

- Add the endpoint constant to [`Endpoints.swift`](../Packages/FlukeKit/Sources/FlukeKit/API/Endpoints.swift).
- Add the DTO struct to `FlukeKit/Models/`.
- If caching is needed, add a `@Model` to `FlukeKit/Persistence/`.
- Wrap it in a repository in `FlukeKit/Repositories/`.
- Test the repository with `MockURLProtocol` (HTTP) + in-memory `ModelContainer` (cache).

### 3. Build the view bottom-up

- New components → `FlukeUI/Components/` (with snapshot tests).
- Feature view + view model → `FlukeFeatures/<Feature>/`.
- Screens take a repository in their initializer (constructor injection).

### 4. Wire it into the app

- Add to `App/Fluke/RootScene.swift` if it's a tab.
- Add to a parent navigation stack (`.navigationDestination(for: ...)`) if it's a pushed view.
- Add to `App/Fluke/AppEnvironment.swift` if there's a new long-lived service.

### 5. Test the integration

Run on simulator. Walk the user flow end-to-end. If you have an XCUITest covering the flow, run it.

### 6. Update docs

If your feature changes architecture or adds a new component, update [`architecture.md`](architecture.md) and/or [`design-system.md`](design-system.md).

## Working with the backend

The iOS app talks to the existing Fluke API at `../fluke/apps/api`. To run end-to-end:

```bash
# Terminal 1: API
cd ../fluke
pnpm install
pnpm db:seed   # populates whales + sightings; only needed first run
pnpm dev       # localhost:4000

# Terminal 2: iOS app — open Xcode, ⌘R
```

API changes that the iOS app needs go in the parent `fluke` repo. The plans for B-API-1 (observer auth, M-iOS-3) and B-API-2 (`/whales/:id/track`, `/sightings/me`, M-iOS-5) detail the schema and route changes. Coordinate API changes with the web team — both apps consume the same surface.

## Code review

### When does a change need review

- All PRs touching shared modules.
- All schema migrations (in the parent `fluke` repo).
- Anything affecting auth or persistence.
- Visual changes — at minimum, a snapshot test diff in the PR.

### What reviewers look for

1. **Spec compliance** — does the diff match the plan task it claims to implement?
2. **Boundary discipline** — no `import FlukeKit` from `FlukeUI`; no cross-feature imports.
3. **TDD evidence** — is the test in the diff? Does it actually test behavior (not just mocks)?
4. **File size + responsibility** — is the new file focused?
5. **Naming** — do identifiers describe the thing rather than how it's implemented?
6. **No dead code** — orphaned files (`Item.swift` from Xcode's SwiftData scaffold is a known exception, removed in M-iOS-2 cleanup).

### Review severity

| Level | Action |
| --- | --- |
| **CRITICAL** | Blocks merge — security, data loss, broken auth |
| **HIGH** | Should fix before merge — wrong behavior, broken pattern |
| **MEDIUM** | Consider fixing — maintainability concern |
| **LOW** | Optional — style suggestion |

## Branching and PRs

- Default branch: `main`.
- Feature branches: `m-ios-N/<task>` (e.g. `m-ios-2/sightings-map`).
- Hotfixes: `fix/<short-description>`.
- PRs target `main`. Squash-merge if the branch has noise; otherwise rebase-merge to preserve task-by-task history.

A PR description should reference the plan task it implements:

```markdown
## What

Implements M-iOS-2 Task 9 (SightingsMapView) per `docs/plans/m-ios-2-sightings-whales-learn.md`.

## How

- Wraps `MLNMapView` in a `UIViewRepresentable`.
- Coordinator handles tap → emits via closure.
- Markers rendered from `MapMarker` via `ImageRenderer`.

## Test plan

- [ ] All 3 package tests green (`for pkg in FlukeKit FlukeUI FlukeFeatures; do (cd Packages/$pkg && swift test); done`)
- [ ] Xcode workspace test green (`xcodebuild test -workspace Fluke.xcworkspace -scheme Fluke ...`)
- [ ] Manual: tap a marker, sheet presents
```

## Releasing

Production releases ship via TestFlight → App Store. The release workflow lives in [`build-and-ci.md`](build-and-ci.md). M-iOS-7 covers the App Store submission flow.

## Questions / pushback

If a plan task feels wrong, **escalate before implementing**. The plan is the contract; if the contract is broken, fix the plan, not the code-vs-plan mismatch.

When in doubt: small commits, frequent runs, ask early.
