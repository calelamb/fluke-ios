# Fluke iOS — App Store readiness triage

**Date:** 2026-07-09  
**Repo state:** `main` @ `9bd94cd` (Atlas container landed; App shell still Xcode template)  
**Verdict:** Not App Store ready. Packages have a solid domain + Atlas prototype; the App target does not yet present a Fluke product. Roughly M-iOS-1 incomplete, with Atlas work ahead of the shell.

---

## Snapshot: what exists vs what ships

| Layer | Status |
| --- | --- |
| **App target** | Still Xcode SwiftData template (`ContentView` + `Item`). No `RootScene`, no `AppEnvironment`, packages **not linked** (`packageProductDependencies = ()`). |
| **FlukeKit** | `APIClient`, `APIError`, DTOs, Atlas-oriented repos (`Whales`, `HistoricalSightings`, `Prediction`). No `Persistence/`, `Auth/`, `SightingsRepository`, `SubmissionsRepository`, multipart upload, or retry. |
| **FlukeUI** | Tokens, `DorsalFinShape`, `SalishSeaShape`, `PlaceholderScreen`, Atlas widgets (`HeatCell`, `ConfidenceCone`, `PodLegend`, `DateScrubber+Atlas`). Missing M-iOS-2–6 components (`MapMarker`, buttons, form fields, etc.). |
| **FlukeFeatures** | Five tab **placeholders**. **Atlas** (Timeline / Range / Trace / Predict) implemented in-package but **unreachable** from App. No Sightings/Whales/Learn/Identify/You/Submit/MovementTrack product screens. |
| **CI** | Package + app test workflow exists; signing disabled. No TestFlight/fastlane. |
| **Assets** | Placeholder app icon + Fraunces font present. No privacy manifest, entitlements, or real `Info.plist`. |

**Working product today:** none end-to-end. Launching the app shows the template item list, not Fluke.

---

## Triage priority key

| Priority | Meaning |
| --- | --- |
| **P0** | Blocks any dogfoodable / TestFlightable product |
| **P1** | Required for a coherent v1 App Store submission |
| **P2** | Required for review compliance / production ops |
| **P3** | Polish, reach, Phase-2 (can ship without, or defer) |

---

## P0 — Finish the shell so anything can run

These are incomplete M-iOS-1 items. Until they land, Atlas and every tab are dead code from the user's perspective.

| ID | Gap | Evidence | Suggested action |
| --- | --- | --- | --- |
| **P0-1** | App target not linked to `FlukeKit` / `FlukeUI` / `FlukeFeatures` | `App/Fluke.xcodeproj/project.pbxproj` — empty `packageProductDependencies` | Wire local SPM products into Fluke target |
| **P0-2** | No `RootScene` (5-tab shell) | Absent; `FlukeApp` presents `ContentView` | Replace template with `TabView` + `NavigationStack` per tab |
| **P0-3** | No `AppEnvironment` / DI | Absent | Construct `APIClient` + repos; inject via environment |
| **P0-4** | `ContentView` / `Item.swift` template residue | `App/Fluke/ContentView.swift`, `Item.swift` | Delete after RootScene lands |
| **P0-5** | No `Info.plist` / `FlukeAPIBaseURL` | `GENERATE_INFOPLIST_FILE = YES`; README claims plist that isn't there | Add plist (or INFOPLIST_KEY) with API base URL |
| **P0-6** | Font registration never called | Documented for `RootScene.onAppear` | Call `FlukeUIFontRegistration.registerIfNeeded()` at launch |
| **P0-7** | Atlas not reachable | Zero `Atlas` references under `App/` | After shell: present `AtlasView` (sheet/fullScreen) from a real entry point once catalog loads |

**Done when:** ⌘R shows five Fluke tabs (placeholders OK) + API client configured; packages import cleanly.

---

## P1 — Core product features (v1 surface)

Roadmap from docs: M-iOS-2 → M-iOS-6. None of these are product-ready.

### Tabs & flows

| ID | Feature | Current | Milestone | Notes |
| --- | --- | --- | --- | --- |
| **P1-1** | **Sightings** | Placeholder | M-iOS-2 | Need map + list + detail; `SightingsRepository`; MapLibre (or decide Atlas-style basemap is enough for v1 — see P3-1) |
| **P1-2** | **Whales** | Placeholder | M-iOS-2 | Catalog, search, profile; expand `WhalesRepository` (cache/search) |
| **P1-3** | **Learn** | Placeholder | M-iOS-2 | Content screens |
| **P1-4** | **You** | Placeholder | M-iOS-3 | Account, Sign in with Apple, my sightings |
| **P1-5** | **Submit** | Missing entirely | M-iOS-4 | Sheet from Sightings `+`; photo + location; offline queue |
| **P1-6** | **Movement Tracks** | Partial as Atlas Trace | M-iOS-5 | Productize entry from whale profile; docs still say `MovementTrack/` |
| **P1-7** | **Identify** | Placeholder | M-iOS-6 | Camera → server ID; multipart on `APIClient` |
| **P1-8** | Design-system components for above | Mostly missing | M-iOS-2–6 | `EcotypeBadge`, `MapMarker`, `SearchField`, `FilterChip`, `PrimaryButton`, `SecondaryButton`, `FormField`, `QueueBadge`, `DisclaimerRibbon`, `ConfidenceBar` |

### Data layer supporting P1

| ID | Gap | Milestone |
| --- | --- | --- |
| **P1-9** | SwiftData `Persistence/` + cache-on-failure repos | M-iOS-2 |
| **P1-10** | `SightingsRepository` / `SubmissionsRepository` | M-iOS-2 / M-iOS-4 |
| **P1-11** | `AuthService` + `AuthSession` + SIWA | M-iOS-3 (+ backend B-API-1) |
| **P1-12** | `NetworkMonitor` + offline photo queue / replay | M-iOS-4 |
| **P1-13** | Multipart upload on `APIClient` | M-iOS-4 / M-iOS-6 |
| **P1-14** | API retry on transient network errors (documented, not implemented) | M-iOS-2 |

### Atlas (already built — make it shippable)

Atlas is the most complete feature module, but not product-ready:

| ID | Gap | Severity inside Atlas |
| --- | --- | --- |
| **P1-15** | Wire into App + inject catalog via `WhalesRepository.fetchAll()` | Blocker for Atlas |
| **P1-16** | Loading / error / empty UI on Timeline, Range, Trace, Predict (VMs often have state; views ignore it) | High |
| **P1-17** | Timeline: wire `PodLegend` / `togglePod`; Predict: whale subject unused | Medium |
| **P1-18** | Range heatmap uses ad-hoc grid math instead of `SalishSeaProjection` — likely misaligned | High |
| **P1-19** | Top chrome overlap (Atlas shell + sub-view controls both at top) | High |
| **P1-20** | ViewModel unit tests missing for all four Atlas VMs | Medium |
| **P1-21** | Prediction disclaimer is inline copy only — need `DisclaimerRibbon` + stronger “not for navigation/safety” language | High (review risk) |

**Minimum lovable product (MLP) recommendation:** Finish P0, then ship **Sightings + Whales + Atlas Trace/Timeline** before Identify/Submit if you want a browse-first v1. Submit + auth are required if the App Store pitch includes citizen-science contribution.

---

## P2 — App Store / production compliance

| ID | Gap | Why it matters |
| --- | --- | --- |
| **P2-1** | Usage description strings (camera, photo library, location) | Crash / rejection when features request permissions |
| **P2-2** | `PrivacyInfo.xcprivacy` | Required privacy manifest |
| **P2-3** | Privacy policy URL (in-app + App Store Connect) | Required with Sign in with Apple / data collection |
| **P2-4** | Terms of Service | Account + UGC apps |
| **P2-5** | Account deletion flow | Apple guideline for apps with accounts |
| **P2-6** | App Privacy nutrition labels mapping | ASC metadata |
| **P2-7** | Production HTTPS API base URL + build configs (Debug/Staging/Release) | Cannot ship pointing at localhost |
| **P2-8** | Code signing + certificates + ASC app record | TestFlight |
| **P2-9** | fastlane / `testflight.yml` on tag | Documented for M-iOS-7; absent |
| **P2-10** | Final app icon (+ tinted variants) | Placeholder OK for TestFlight; final for store |
| **P2-11** | ASC screenshots, description, support URL, age rating | Process, not code |
| **P2-12** | Identify / prediction / citizen-science disclaimers | Misleading claims risk |
| **P2-13** | Backend readiness: B-API-1 (observer auth), B-API-2 (track + my sightings) | iOS features depend on parent `fluke` API |

---

## P3 — Polish, architecture debt, deferred

| ID | Gap | Notes |
| --- | --- | --- |
| **P3-1** | **MapLibre vs custom basemap** | README promises MapLibre + OpenFreeMap; Atlas uses hand-drawn `SalishSeaShape`. Decide: keep custom for Atlas, MapLibre for Sightings — or update docs. |
| **P3-2** | **`FlukeUI` depends on `FlukeKit`** | Violates architecture rule #2 (`ConfidenceCone` takes `PredictionCell`). Move domain-aware views to Features or pass primitives. |
| **P3-3** | Deployment target **iOS 26** on App vs **iOS 17** on packages | Huge reach hit; re-evaluate at M-iOS-7 |
| **P3-4** | Dynamic Type on Fraunces display tokens | Fixed sizes today |
| **P3-5** | Reduce Motion / VoiceOver audit | Only polyline layer respects reduce motion; no a11y labels |
| **P3-6** | Dark mode token variants | Explicitly Phase 2 |
| **P3-7** | Push, iPad layout, Watch, widgets | Out of scope per architecture |
| **P3-8** | On-device ML for Identify | Deferred; server-side Modal |
| **P3-9** | Multiplatform target bloat (macOS/visionOS in pbxproj) | Trim to iPhone-first |
| **P3-10** | XCUITest critical flows | Docs describe them; App UI tests are still template stubs |
| **P3-11** | Docs drift | README “shipping M-iOS-1” vs incomplete shell; MovementTrack vs Atlas naming |

---

## Suggested sequencing

```
1. P0  Finish M-iOS-1 shell (wire packages, RootScene, AppEnvironment, plist)
2. P1  M-iOS-2 Sightings + Whales + Learn (+ SwiftData)
3. P1  Productize Atlas entry (from Whales) + P1-15…P1-21 polish
4. P1  M-iOS-3 Auth / You  (+ backend B-API-1)
5. P1  M-iOS-4 Submit + offline
6. P1  M-iOS-5 Movement Tracks (or fold into Atlas Trace)
7. P1  M-iOS-6 Identify + disclaimers
8. P2  M-iOS-7 privacy, signing, TestFlight, production URL, ASC metadata
9. P3  A11y, deployment target, architecture cleanup, MapLibre decision
```

### Immediate next 5 tasks (dogfood path)

1. Link FlukeKit / FlukeUI / FlukeFeatures to the App target.  
2. Add `AppEnvironment` + `RootScene`; delete `ContentView`/`Item`.  
3. Add `Info.plist` with `FlukeAPIBaseURL`.  
4. Present Atlas from a temporary debug entry (or Whales placeholder CTA) to validate API + basemap on device/simulator.  
5. Add Atlas load/error/empty UI + fix Range projection (P1-16, P1-18).

---

## Open decisions (need product call)

1. **v1 scope:** Browse-only (Sightings/Whales/Atlas) vs full citizen-science (Submit + Auth + Identify)?  
2. **Basemap strategy:** MapLibre for Sightings, custom for Atlas — or one stack?  
3. **Atlas in v1?** Ship as hero feature or keep internal until tabs exist?  
4. **Deployment target:** Stay on iOS 26 for Foundation Models later, or drop to 17 for reach?  
5. **Parent API:** Confirm B-API-1 / B-API-2 status in `calelamb/fluke` (not accessible from this agent’s token).

---

## Evidence index

| Claim | Where |
| --- | --- |
| App is template | `App/Fluke/FlukeApp.swift`, `ContentView.swift` |
| Packages unlinked | `project.pbxproj` `packageProductDependencies = ()` |
| Tab placeholders | `Packages/FlukeFeatures/.../*Placeholder.swift` |
| Atlas implemented | `Packages/FlukeFeatures/Sources/FlukeFeatures/Atlas/` |
| No Auth / Persistence | No `FlukeKit/Auth/` or `Persistence/` directories |
| No MapLibre dep | No MapLibre in any `Package.swift` / pbxproj |
| Architecture rules | `docs/architecture.md` |
| Milestone map | `docs/design-system.md`, `docs/build-and-ci.md`, README Status |
| Icon + font present | `AppIcon.appiconset/icon-1024.png`, `Resources/Fonts/Fraunces-Variable.ttf` |
