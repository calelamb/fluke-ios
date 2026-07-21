# Task 5B Atlas Signature Experience Report

## Status

DONE

Base commit: `82e3161`

## Scope delivered

- Preserved the existing full-screen Atlas route and close control from the Sightings globe action. The root toolbar already owns the approved Atlas/Add Sighting actions, so this task did not alter `RootScene`, `AppEnvironment`, or the Xcode project.
- Kept the exact mode order `Timeline`, `Range`, `Trace`, `Predict`, with Timeline as the default and Trace used only for an explicit whale route.
- Added a fixed Salish Sea viewport and clamped all track and prediction geometry to its normalized bounds.
- Composed Timeline date and pod filters, Range month and pod filters, stable Trace whale identity, and Predict whale and pod subjects.
- Added bounded heatmap intensity and prediction confidence presentation, including safe empty-data behavior with no division by zero.
- Reframed prediction content as a historical estimate and explicitly stated that it is not a current position.
- Added the PNW editorial pass: Fraunces italic geography, subtle bathymetric bands, a shared translucent control shelf, and consistent J/K/L/Bigg's pod legends.
- Added concise visible and VoiceOver-readable summaries while hiding decorative map geometry from accessibility traversal.
- Stopped dashed path flow and endpoint motion when Reduce Motion is enabled.
- Added accessibility-size menus/vertical controls and maintained 44-point minimum interactive targets.
- Preserved the existing stale, offline, loading, unavailable, sparse, and empty-state truth.
- Composed offline/stale notices and mode-specific empty or sparse truth independently, so a connectivity notice never hides what is known about the selected Atlas mode.

## TDD evidence

RED was observed before implementation:

- `swift test --package-path Packages/FlukeFeatures --filter AtlasProductTests` failed to compile for the intentionally missing projection, presentation, summary, normalization, and Reduce Motion APIs.
- `swift test --package-path Packages/FlukeUI --filter AtlasVisualSnapshotTests` failed because no approved reference image existed and recorded the first candidate.
- A later focused RED, `swift test --package-path Packages/FlukeFeatures --filter predictionCellClamping`, failed for the intentionally missing prediction clamp API.

GREEN after implementation:

- `AtlasProductTests`: 19/19 pass.
- `AtlasVisualSnapshotTests`: 1/1 pass against the inspected deterministic reference image.
- `AtlasFeatureSnapshotTests`: 5/5 pass against separate inspected references for Timeline, Range, Trace, Predict, and accessibility text sizing. These render the real Atlas feature subviews and their basemap, controls, legends, summaries, notices, and empty/sparse truth.

## Independent review remediation

- Fixed notice-first rendering in all four modes. Cached-offline and stale notices now remain visible alongside confirmed empty or sparse truth.
- Added focused product tests for the offline/stale composition matrix and preserved Predict's injected subject/state ordering.
- Added deterministic snapshots of the actual Atlas feature compositions rather than relying only on the FlukeUI component gallery.
- Split references by mode so a localized visual regression cannot disappear inside a single tall image comparison.

## Final verification

- `swift test --package-path Packages/FlukeFeatures --enable-code-coverage`: PASS, 97 Swift Testing tests plus the XCTest suites, including 5/5 real Atlas feature snapshots.
- `swift test --package-path Packages/FlukeUI --enable-code-coverage`: PASS, 22/22 XCTest tests including both Atlas snapshot suites.
- `scripts/verify-swift-package-coverage.sh` for selected FlukeFeatures logic: PASS, 90.30% (`1247/1381`, 15 files).
- `scripts/verify-swift-package-coverage.sh` for FlukeUI sources: PASS, 93.33% (`532/570`, 15 files).
- `scripts/verify-contract-fixtures.sh --no-upstream`: PASS, canonical manifest matched.
- `xcrun swift-format lint --strict` across every touched Swift file: PASS.
- `git diff --check`: PASS.
- Debug build for iPhone 17 / iOS 26.0.1 simulator with signing disabled: PASS.
- Existing app UI flow `testPublicBrowseTabsAreReachable`: BLOCKED by the local simulator accessibility service before assertions. Fresh attempts on iPhone 17 and iPhone 17 Pro both reported `kAXErrorServerNotFound`; an intervening retry was killed by the simulator runner. The app itself builds successfully for iPhone 17, and this infrastructure failure is recorded rather than misreported as a green UI test.

## Files changed

- Atlas container, projection, basemap, polyline, and all four mode views/view models under `Packages/FlukeFeatures/Sources/FlukeFeatures/Atlas/`.
- `Packages/FlukeFeatures/Tests/FlukeFeaturesTests/AtlasProductTests.swift`.
- `Packages/FlukeFeatures/Tests/FlukeFeaturesTests/AtlasFeatureSnapshotTests.swift` and five checked-in PNG references.
- `Packages/FlukeFeatures/Package.swift` excludes snapshot references from test resources.
- `Packages/FlukeUI/Tests/FlukeUITests/AtlasVisualSnapshotTests.swift` and its checked-in PNG reference.

## Concerns

No code concerns remain within Task 5B scope. The app UI-route gate must be rerun after the local CoreSimulator/Xcode accessibility service is healthy; it is not green in this checkout.
