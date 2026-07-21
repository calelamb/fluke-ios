# iOS Task 6 implementation report

## Scope

Implemented Task 6 only: full-launch accessibility, privacy, and permission auditing. No App Store
Connect changes or uploads were made.

## TDD evidence

- Privacy verifier RED: `scripts/tests/full-launch-privacy-tests.sh` failed all six cases because the
  production verifier was absent. GREEN: all positive and mutation cases pass.
- Accessibility UI RED: pinned iPhone 17 / iOS 26.0.1 produced 0/2 passing tests. Failures exposed
  the absent accessibility-size Atlas mode seam and disabled-Identify test contract. Iteration also
  found a transient tab-bar hittability wait and an Atlas menu-item animation wait; the final test
  waits for actual hittability rather than weakening reachability assertions.
- Queue announcement RED: `SubmissionAccessibilityTests` failed to compile because
  `SubmissionFlushAnnouncement` was absent. GREEN proves singular/plural confirmed-upload copy and
  silence when no queued item completed.
- Coarse coordinate RED: a map coordinate retained six decimal places (`48.123456`, `-123.987654`).
  GREEN rounds map-selected coordinates to two decimal places before binding and submission, making
  the coarse-location declaration behaviorally true.

## Product changes

- Declares linked email, optional name, submitted photos/videos, and coarse submitted location for
  app functionality only; tracking and tracking domains remain absent.
- Exact verifier rejects disabled ATS, location permission copy, broad photo-library permission copy,
  ATT usage, tracking, incorrect Sign in with Apple entitlement, missing/extra collection categories,
  or non-app-functionality purposes. CI runs both verifier tests and the production verifier.
- Camera copy is action-specific. Selection-only `PhotosPicker` requires no broad library permission;
  shipping disabled Identify exposes no camera/photo actions and requests no permission.
- Adds explicit 44-point Atlas accessibility menu at accessibility Dynamic Type, meaningful containers
  for Timeline/Range/Trace/Predict, opaque Atlas controls under Reduce Transparency, decorative map
  layers skipped, and escape actions for Atlas, Movement, unavailable Movement, and dirty-guarded
  Submit.
- Submit moves accessibility and keyboard focus to the first invalid field, disables validation scroll
  animation under Reduce Motion, announces submitted/queued/partial results, and the shell announces
  only confirmed queue flush completions. Photo actions have explicit 44-point minimum heights.
- Adds the physical-device pre-submission checklist at
  `docs/superpowers/task6-accessibility-manual-checklist.md`.

## Fresh verification

- `scripts/tests/verification-scripts-tests.sh`: passed.
- `scripts/tests/full-launch-privacy-tests.sh`: passed.
- `scripts/verify-full-launch-privacy.sh`: passed.
- `scripts/verify-contract-fixtures.sh --no-upstream`: passed.
- FlukeKit package: 173 total XCTest/Swift Testing tests passed; source coverage 92.03% (1860/2021).
- FlukeUI package: 22 tests passed; source coverage 93.33% (532/570), including accessibility XXXL,
  increased contrast, and Reduce Motion snapshots.
- FlukeFeatures final package: 109 total XCTest/Swift Testing tests passed; selected logic coverage
  90.30% (1247/1381). Atlas feature snapshots passed, including accessibility text.
- Final accessibility UI result `build/task6-final-accessibility-ui.xcresult`: 2/2 passed, 0 failed on
  pinned iPhone 17 / iOS 26.0.1. It reaches five tabs, Add Sighting, Atlas, and all four Atlas modes at
  accessibility XXXL with Reduce Motion, Reduce Transparency, and Increased Contrast; disabled
  Identify has no media permission UI.
- Final app result `build/task6-final-app-tests.xcresult`: 60 parameterized test runs represented by
  46 test cases, 0 failures. `Fluke.app` line coverage 81.10% (1030/1270).
- Final Release simulator build: passed with code signing disabled.
- `plutil -lint` for Info, privacy manifest, and entitlements: passed.
- `git diff --check`: passed. Targeted secret/ATS/location/ATT scan found no shipped secret or privacy
  override.

## Manual and policy gates

- A physical-iPhone VoiceOver/XXXL/Increase Contrast/Reduce Transparency/Reduce Motion traversal was
  not executed in this environment. The explicit checklist remains a required pre-submission gate;
  simulator automation is not represented as physical-device evidence.
- The requested Task 6 contract explicitly requires exactly four collected-data categories. Code also
  receives an authenticated observer `id` and accepts optional free-text sighting notes. Depending on
  App Store Connect's data-type interpretation and server retention, independent review may require
  adding User ID and Other User Content to both the manifest/verifier and nutrition-label answers.
  This report does not silently broaden or conceal that policy decision.
