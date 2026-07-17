# Native Release A Browse Design

## Objective

Replace every shipping placeholder with a native, read-only SwiftUI experience backed by the certified Fluke API and the existing resilient cache. Release A exposes exactly four tabs: Sightings, Whales, Learn, and Atlas. Accounts, submissions, identification, observer routes, and their presentation remain outside the app target.

## Architecture

Each network-backed feature owns a focused `@MainActor @Observable` view model. View models depend on the existing `SightingsRepositoryProtocol`, `WhalesRepositoryProtocol`, `HistoricalSightingsRepositoryProtocol`, or `PredictionRepositoryProtocol`, never concrete transports. They translate `BrowseResult` into an immutable presentation state that retains valid cached content while separately describing freshness, offline status, and recoverable failure. Views render those states and send explicit load, refresh, retry, selection, search, and filter actions back to the view model.

Shared browse UI belongs in FlukeFeatures and consists of small state banners, loading/empty/error presentations, ecotype badges, map markers, and section surfaces. FlukeKit remains UI-free. FlukeUI remains a reusable visual system and owns only generic tokens and controls.

## Sightings

Sightings opens in List mode with a List/Map picker that remains reachable at large Dynamic Type sizes. One load combines approved Fluke sightings with the external public feed. List rows show observation date, location fallback, group size, ecotype, and known whales without inventing unavailable data. Map mode uses the rights-clear local Salish Sea basemap and projected accessible markers; it does not introduce an unvetted tile or imagery dependency. Selecting a row or marker opens the same native detail sheet.

Fresh data has no warning. Stale cached data remains visible with the safe refresh failure. Offline cached data remains visible with an offline banner. Empty data gets an honest empty state. Failure without cache gets a retry action. Pull-to-refresh and Retry invoke the same deterministic load path, and overlapping requests do not overwrite newer state.

## Whales

Whales presents a searchable catalog with All, Resident, Bigg's, Offshore, and Unknown filters. Search matches catalog ID, common name, pod, and ecotype using localized case- and diacritic-insensitive matching. Cards use the existing PNW palette, locally drawn fin mark, and remote hero image only through an HTTP(S) URL already validated by FlukeKit. Text remains the complete fallback when an image is absent or fails.

Selecting a whale opens a profile loaded through the cached repository. The profile renders identity, life metadata, biography, distinguishing marks, mother and offspring, notable events, recent sightings, and source citations. Missing optional fields remove their section rather than displaying placeholder copy. A See movement action opens Atlas Trace for that whale when the catalog selection is available.

## Learn

Learn is local, rights-clear editorial content that explains the catalog vocabulary, sighting evidence, ecotypes, responsible viewing, data freshness, and source policy. It uses reading-width layouts, semantic headings, selectable text, and links only to first-party or clearly attributed public sources. It makes no mutation or identification promises.

## Atlas

Atlas retains Timeline, Range, Trace, and Predict as public data modes. Its catalog is loaded through the whale repository so Timeline can resolve pod membership and Trace can select a real whale. Each mode consumes resilient `BrowseResult` values rather than bypassing the cache. Timeline and Range use historical sightings; Trace uses cached whale tracks; Predict uses certified prediction responses. All modes show loading, empty, stale, offline, error, and retry states without erasing valid cached content.

Map animation stops when Reduce Motion is enabled. Date, pod, month, whale, horizon, and mode controls have explicit VoiceOver labels, values, and selected traits. Sparse tracks show an honest read-only explanation without a submission call to action.

## Accessibility and visual behavior

The visual language stays editorial PNW: fog and bone surfaces, abyss text, tide interaction color, ember used sparingly, Fraunces display type, and system body text. There are no decorative emoji or downloaded assets. Body copy and controls use Dynamic Type styles; layouts reflow instead of clipping. Every icon-only action has a label, marker order follows chronological/list order, and compound rows expose one concise accessibility element. Interactive controls meet a 44-point target. Motion is conditional on `accessibilityReduceMotion`.

Search uses the native searchable field, preserves a visible focus treatment, supplies a clear action, and does not trigger network requests per keystroke. Empty filtered results are distinguished from an empty server result.

## Boundaries and verification

The Release A boundary script rejects shipping placeholder types, `PlaceholderScreen` usage from FlukeFeatures, obsolete Identify/You feature source folders, Release B imports, and observer/mutation routes. Root shell tests continue to prove exactly four tabs.

TDD covers view-model freshness mapping, stale/offline retention, retry, cancellation ordering, search/filter behavior, detail state, Atlas state mapping, and read-only Learn content. Lightweight render tests instantiate each shipping surface. Package tests, FlukeKit coverage, script self-tests, pinned simulator app tests, the Release build, and the built production API origin are required before the implementation commit.

## Submission boundary

This slice makes the unsigned app functionally complete for public Release A browsing. TestFlight still requires external Apple Developer team access, distribution signing material, an App Store Connect record, privacy and listing metadata, and a signed archive/upload. Those external credentials are not added to source control.
