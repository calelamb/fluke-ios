# Task 3 Implementation Report

## Status

DONE_WITH_CONCERNS

Task 3 provides immutable validated submission values, normalized photos, a strict API wire DTO, two-stage idempotent submission, actor-isolated SwiftData persistence, atomic photo storage, coalesced replay, the Submit sheet, system PhotosPicker selection, user-initiated camera capture, and one shared queue for replay, account cleanup, and You/Logbook rows.

Production submission routes were not called. HTTP behavior is contract-tested with injected transports; this report does not claim live API integration.

## Review Fixes

- Removed the unsupported background `URLSession`/`data(for:)` combination. Live submission and launch/foreground/network replay now use a normal default session with bounded waits-for-connectivity behavior. Durable queue storage and all three flush triggers remain.
- Added an actor in-flight gate. Concurrent `flush()` calls coalesce, proven with a blocked-service test that records one submission.
- Fixed post-move and temporary-file cleanup. Discard first persists a `.discarding` tombstone, retains the row if byte removal fails, and deletes the row only after removal. Partial cleanup filenames remain durably tracked until deletion succeeds.
- Added stable per-photo UUIDs that survive queue persistence and partial replay. Photo requests send `Idempotency-Key: <clientSubmissionId>:<photoIdempotencyUUID>`; the API photo route must deduplicate this key within the parent sighting.
- Added a shared 10,000,000-byte mutation limit and a processed-photo limit of 9,997,952 bytes, reserving 2,048 bytes for worst-case multipart framing.
- Added the missing Submit state-machine tests and reached the exact CI Feature logic gate.
- The location map now commits its center coordinate on camera changes and uses a visible center pin.
- Terminal success, queued, and partial states dismiss without discard confirmation.
- Photo load/process failures and camera denied/restricted/unavailable states now surface bounded user-facing copy.
- Signed-in forms hide the email field but submit the authenticated account email required by the API contract.
- Added a dedicated `SubmitSightingRequest` wire DTO matching the strict API schema: `clientSubmissionId`, ISO-8601 `observedAt`, `latitude`, `longitude`, optional `locationName`, `groupSize`, `behaviorNotes`, and required `observerEmail`. Queue-only `photoCount` and `existingReceipt` are never serialized.
- Aligned group-size validation and UI bounds to the API contract maximum of 100. Submission receipt decoding accepts current camelCase and legacy queued snake_case tokens.

## Recorded RED / GREEN Evidence

### Original Task 3 cycles

- RED: `swift test --package-path Packages/FlukeKit --filter 'SubmissionValidatorTests|SubmissionServiceTests|ImageProcessorTests'`
  - Exit 1 for missing submission types.
- GREEN: same command.
  - Exit 0, 7 tests passed.
- RED: `swift test --package-path Packages/FlukeKit --filter 'SubmissionQueueTests|SubmissionReplayActorTests'`
  - Exit 1 for missing durable queue/replay types.
- GREEN: focused core command.
  - Exit 0, 13 tests passed.
- RED: `swift test --package-path Packages/FlukeFeatures --filter SubmitViewModelTests`
  - Exit 1 for missing Submit state types.
- GREEN: same command.
  - Exit 0, 4 original tests passed.

### Independent-review corrections

- RED: `swift test --package-path Packages/FlukeKit --filter 'SubmissionServiceTests|SubmissionQueueTests|SubmissionReplayActorTests'`
  - Exit 1 for missing photo idempotency/size limits, post-move and removal failure injection, and replay coalescing behavior.
- GREEN: same command after corrections.
  - Exit 0, 12 focused tests passed at that checkpoint.
- RED: `swift test --package-path Packages/FlukeFeatures --filter SubmitViewModelTests`
  - Exit 1 for missing terminal dismissal, signed-in presentation, coordinate selection, and photo/camera failure types.
- GREEN: same command.
  - Exit 0, 12 tests passed.
- RED: targeted `AppEnvironmentTests` Xcode run with the normal-session factory removed.
  - Exit 65; compilation failed on missing `submissionSessionConfiguration`.
- GREEN: `xcodebuild ... test -only-testing:FlukeTests/AppEnvironmentTests CODE_SIGNING_ALLOWED=NO`
  - Exit 0; 6 tests passed, including the non-background live-session assertion.
- RED: `swift test --package-path Packages/FlukeKit --filter 'SubmissionServiceTests|SubmissionValidatorTests'`
  - Exit 1: exact JSON test exposed receipt camelCase decoding, snake_case payload keys/numeric date, and group-size 101 acceptance.
- GREEN: focused FlukeKit wire/validation command plus focused Feature command.
  - Exit 0; 6 FlukeKit tests and 12 Submit state tests passed.

## Final Verification

- `swift test --package-path Packages/FlukeKit --enable-code-coverage`
  - Fresh rerun exit 0: 103 tests in 19 suites passed.
  - The immediately preceding attempt terminated with the existing intermittent Swift Testing signal 11 during unrelated concurrent contract/cache execution; it reported no assertion failure. The complete fresh rerun passed.
- `swift test --package-path Packages/FlukeFeatures --enable-code-coverage`
  - Exit 0: 53 tests in 11 suites passed.
- Exact CI Feature testable-logic coverage command from `.github/workflows/ci.yml`:
  - Exit 0: 84.74% line coverage, 711/839 lines across 13 selected files.
- `xcodebuild -project App/Fluke.xcodeproj -scheme Fluke -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
  - Exit 0: `** BUILD SUCCEEDED **`.
- `xcodebuild -project App/Fluke.xcodeproj -scheme Fluke -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' test -only-testing:FlukeTests CODE_SIGNING_ALLOWED=NO`
  - Exit 0: 21 tests in 4 suites passed; `** TEST SUCCEEDED **`.
- `git diff --check`
  - Exit 0.

The earlier full UI attempt remains recorded as 5/6 passing: `testCaptureAppStoreScreenshots` could not load `04-atlas` because its localhost fixture server at `127.0.0.1:4000` was absent. That is test infrastructure, not a Task 3 assertion failure.

## Coverage

- Exact CI FlukeFeatures selected testable logic: 84.74% lines (711/839 across 13 files), passing the 80% gate.
- `SubmitViewModel.swift`: 88.24% line coverage.
- `PhotoSelectionState.swift`: 90.00% line coverage.
- FlukeKit production aggregate: 93.00% line coverage (88.14% regions, 91.60% functions).
- Full FlukeFeatures production aggregate: 14.64% line coverage. This aggregate honestly includes declarative SwiftUI view bodies, which CI explicitly excludes from the numeric logic gate and covers through build/render/UI checks.

## Commits

- `3b91bd1` — `feat: add validated sighting submission service`
- `e62ee9b` — `feat: add durable offline submission queue`
- `7dc07f4` — `feat: build sighting submission flow`
- `5579dc9` — `fix: harden durable sighting submission`
- `b6b39ae` — `fix: align submission wire contract`

## Remaining Concerns

1. Production submission/photo routes remain unverified from iOS. The API route implementation must honor the documented sighting and per-photo idempotency keys before live certification.
2. The Atlas screenshot UI test requires its local fixture server; the app unit target and final iOS build are green.
3. The Swift Testing runner intermittently emitted signal 11 during highly parallel full FlukeKit coverage runs; immediate complete reruns passed, with no deterministic failing test identified.
