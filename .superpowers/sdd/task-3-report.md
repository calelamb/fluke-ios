# Task 3 Implementation Report

## Status

DONE_WITH_CONCERNS

Task 3 now provides validated immutable submission values, image normalization, a two-stage idempotent mocked API client, an actor-isolated SwiftData queue with atomic photo persistence, serialized replay, a submit state machine and sheet, system PhotosPicker selection, user-initiated camera capture, and one shared queue for replay, account-association cleanup, and You/Logbook queued rows.

No live production submission endpoint was exercised or certified. All submission HTTP behavior is contract-tested with mocked transport.

## RED / GREEN Record

### Submission API and image pipeline

- RED: `swift test --package-path Packages/FlukeKit --filter 'SubmissionValidatorTests|SubmissionServiceTests|ImageProcessorTests'`
  - Exit 1. Compilation failed on the intentionally missing `SubmissionDraft`, `SubmissionValidator`, `SubmissionService`, `ProcessedPhoto`, and `ImageProcessor` types.
- GREEN: same command.
  - Exit 0. 7 tests passed across 3 suites.

### Durable queue and replay

- RED: `swift test --package-path Packages/FlukeKit --filter 'SubmissionQueueTests|SubmissionReplayActorTests'`
  - Exit 1. Compilation failed on the intentionally missing queue, photo-store, value, and replay types.
- GREEN: `swift test --package-path Packages/FlukeKit --filter 'SubmissionValidatorTests|SubmissionServiceTests|ImageProcessorTests|SubmissionQueueTests|SubmissionReplayActorTests'`
  - Exit 0. 13 tests passed across 5 suites.

### Submit state machine

- RED: `swift test --package-path Packages/FlukeFeatures --filter SubmitViewModelTests`
  - Exit 1. Compilation failed because `SubmitViewModel` and its states did not exist.
- GREEN: same command.
  - Exit 0. 4 tests passed in 1 suite.

### Anonymous email regression

- RED: `swift test --package-path Packages/FlukeKit --filter SubmissionValidatorTests`
  - Exit 1. The new nil-email assertion reported that no error was thrown.
- GREEN: included in the final FlukeKit full-suite run after adding the explicit `requiresObserverEmail` boundary.

## Final Verification

- `swift test --package-path Packages/FlukeKit --enable-code-coverage`
  - Exit 0 on the fresh rerun: 98 tests in 19 suites passed.
  - One immediately preceding run terminated with transient signal 11 while unrelated cache tests were executing; no assertion failure was reported, and the fresh full rerun passed.
- `swift test --package-path Packages/FlukeFeatures --enable-code-coverage`
  - Exit 0: 45 tests in 11 suites passed.
- `xcodebuild -project App/Fluke.xcodeproj -scheme Fluke -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
  - Exit 0: `** BUILD SUCCEEDED **` after final integration changes.
- `xcodebuild -project App/Fluke.xcodeproj -scheme Fluke -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' test CODE_SIGNING_ALLOWED=NO`
  - App/unit layer: 20 tests in 4 suites passed.
  - UI layer: 5 of 6 passed. Existing App Store screenshot test `testCaptureAppStoreScreenshots` failed waiting for `04-atlas` because its expected local API at `127.0.0.1:4000` was unavailable; this was not a Task 3 assertion failure.
- `git diff --check`
  - Exit 0.

## Coverage

- FlukeKit production aggregate: 92.57% line coverage (87.98% regions, 91.47% functions).
- FlukeFeatures production aggregate: 14.16% line coverage (16.29% regions, 19.60% functions).
- New FlukeKit submission files are individually 94.59%-100% by line; queue/service/validator region coverage is 85.25%-93.55%.
- `SubmitViewModel` is 77.78% by line. SwiftUI view bodies are not exercised by the package unit runner, so the FlukeFeatures aggregate does not meet the requested 80% threshold.

## Commits

- `3b91bd1` — `feat: add validated sighting submission service`
- `e62ee9b` — `feat: add durable offline submission queue`
- `7dc07f4` — `feat: build sighting submission flow`

## Files

- Submission core: `SubmissionModels.swift`, `SubmissionValidator.swift`, `SubmissionService.swift`, `ImageProcessor.swift`, and the API client header extension.
- Durable persistence: `QueuedSubmission.swift`, `QueuedPhotoStore.swift`, `SubmissionQueue.swift`, `SubmissionReplayActor.swift`.
- UI: `SubmitViewModel.swift`, `SubmitView.swift`, `PhotoPicker.swift`, `LocationPickerView.swift`, `SubmissionSuccessView.swift`.
- Integration: `AppEnvironment.swift`, `RootScene.swift`, `AuthSession.swift`, `DeferredSubmissionQueueBridge.swift`, `Info.plist`, and `AuthSessionTests.swift`.
- Tests: submission validation/service/image/queue/replay tests and submit view-model tests.

## Concerns

1. Production API endpoints remain mocked/not live; idempotency relies on the server honoring `Idempotency-Key` and the receipt/token contract.
2. The FlukeFeatures aggregate and `SubmitViewModel` do not reach 80% coverage, primarily because SwiftUI view bodies have no package-level rendering harness.
3. The full Xcode UI suite needs its local screenshot fixture server to make the Atlas screenshot assertion green.
4. Background URLSession replay is configured in the live environment, but end-to-end relaunch delivery cannot be verified without the production endpoint and an app-lifecycle integration environment.
