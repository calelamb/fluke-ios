# Fluke iOS

Native iOS companion to [Fluke](https://github.com/calelamb/fluke), the Pacific Northwest orca sightings map.

## What this is

A SwiftUI iOS app that pairs with the Fluke website and its standalone API. Release A is a browse-only shell with four tabs: **Sightings**, **Whales**, **Learn**, and **Atlas**. Atlas includes timeline, range, movement-trace, and prediction views. Authenticated mutation features remain isolated in the dormant `FlukeReleaseB` product and are not linked into the app.

## Stack

- **Swift tools 5.10**, verified with **Swift 6.2 / Xcode 26.0.1**, **SwiftUI**, and an **iOS 17+** deployment target.
- **Three local Swift packages** at `Packages/`:
  - `FlukeKit` — pure-Swift domain layer (API client, models, persistence). No SwiftUI imports.
  - `FlukeUI` — design system (color/font/animation tokens, `DorsalFinShape`, components). SwiftUI-only.
  - `FlukeFeatures` — feature modules, one folder per tab. Depends on Kit + UI.
- **Backend:** [`calelamb/fluke-api`](https://github.com/calelamb/fluke-api), cloned locally as the sibling directory `../fluke-api`.
- **Map basemap:** [MapLibre Native iOS](https://github.com/maplibre/maplibre-gl-native-distribution) with [OpenFreeMap](https://openfreemap.org/) tiles.
- **No third-party HTTP library** — `URLSession` directly.

## Quick start

1. Open [`Fluke.xcworkspace`](./Fluke.xcworkspace) in **Xcode 26.0.1**.
2. Pick an iPhone 17 (or newer) simulator from the scheme dropdown.
3. ⌘R.

To talk to the local API:

```bash
cd ../fluke-api
pnpm install --frozen-lockfile
pnpm db:generate
pnpm db:migrate:deploy
pnpm db:seed   # populates whales + sightings
pnpm dev       # API runs on http://localhost:4000
```

The Debug API base is `http://localhost:4000`; Release uses the certified production origin `https://fluke-api.onrender.com`. Both flow through `FLUKE_API_BASE_URL` in the build-specific xcconfig and `App/Fluke/Info.plist`. Staging remains intentionally non-deployable until its own origin is certified.

## API contracts

[`fluke-api`](https://github.com/calelamb/fluke-api) is the source of truth for API schemas and deterministic contract fixtures. `FlukeKit` decodes exact copies of the released fixtures so a backend shape change fails in the client test suite before release.

After changing and releasing an API contract, refresh the iOS copies from sibling clones and run both package suites:

```bash
cp ../fluke-api/contracts/fixtures/*.json Packages/FlukeKit/Tests/FlukeKitTests/Fixtures/
for fixture in ../fluke-api/contracts/fixtures/*.json; do
  cmp "$fixture" "Packages/FlukeKit/Tests/FlukeKitTests/Fixtures/$(basename "$fixture")"
done
scripts/verify-contract-fixtures.sh
swift test --package-path Packages/FlukeKit
swift test --package-path Packages/FlukeFeatures
```

Do not hand-edit the copied JSON or add client-only fields. Update the API contract and regenerate its artifacts first, then align the explicit Swift DTOs and `contracts/api-fixtures.sha256` to the released shape. CI validates the packaged set against that canonical manifest without requiring private cross-repository credentials. When a sibling API checkout is available, the verifier additionally requires exact filenames and bytes; that local check is a release checkpoint until an explicit read token is configured.

## Documentation

| Doc | What it covers |
| --- | --- |
| [`docs/architecture.md`](docs/architecture.md) | Package boundary, dependency rules, how new code lands in the right module |
| [`docs/design-system.md`](docs/design-system.md) | Color/font/animation tokens, `DorsalFinShape`, components reference |
| [`docs/contributing.md`](docs/contributing.md) | Why the project doesn't take outside contributions, and the code conventions it follows |
| [`docs/testing.md`](docs/testing.md) | Test strategy, snapshot testing, MockURLProtocol, coverage targets |
| [`docs/build-and-ci.md`](docs/build-and-ci.md) | Local builds, simulator targets, CI workflow, deployment target rationale |

The full design spec lives at [`../fluke/docs/specs/ios-app.md`](../fluke/docs/specs/ios-app.md) in the main Fluke repository.

## Project layout

```
fluke-ios/
├── Fluke.xcworkspace/                  # ← open this in Xcode
├── App/
│   ├── Fluke.xcodeproj/                # iOS app target
│   └── Fluke/
│       ├── FlukeApp.swift              # @main entry
│       ├── RootScene.swift             # four-tab Release A shell
│       ├── AppEnvironment.swift        # fail-closed configuration + DI
│       ├── Assets.xcassets/            # AppIcon + tinted variants
│       └── Info.plist
├── Packages/
│   ├── FlukeKit/                       # domain layer
│   │   ├── Sources/FlukeKit/
│   │   │   ├── API/                    # APIClient, APIError, Endpoints
│   │   │   ├── Models/                 # Whale, Sighting, Ecotype, …
│   │   │   ├── Services/               # JSONDecoder.fluke
│   │   │   └── Persistence/            # Versioned actor-backed browse cache
│   │   ├── Sources/FlukeReleaseB/      # dormant DTO/endpoint product; not app-linked
│   │   └── Tests/FlukeKitTests/
│   ├── FlukeUI/                        # design system
│   │   ├── Sources/FlukeUI/
│   │   │   ├── Tokens/                 # Color, Font, Animation
│   │   │   ├── Shapes/                 # DorsalFinShape
│   │   │   ├── Components/             # Atlas visualization components
│   │   │   └── Resources/Fonts/        # Fraunces-Variable.ttf
│   │   └── Tests/FlukeUITests/
│   │       └── __Snapshots__/          # snapshot-testing PNG references
│   └── FlukeFeatures/                  # feature modules
│       └── Sources/FlukeFeatures/
│           ├── Sightings/
│           ├── Whales/
│           ├── Learn/
│           └── Atlas/
├── docs/                               # ← engineering docs
├── scripts/                            # verification and asset generators
└── .github/workflows/ci.yml            # GitHub Actions test workflow
```

## Status

Release A ships four real public browsing surfaces: a merged sightings list/map, searchable whale catalog and profiles, a locally authored Learn reader, and the public movement Atlas. Every network-backed surface distinguishes fresh, stale, offline, empty, loading, and failed states while retaining last-known-good data. Deterministic API fixtures, resilient read-only persistence, and fail-closed environment configuration protect that boundary. See [`docs/build-and-ci.md`](docs/build-and-ci.md) for the exact verification and submission-readiness state.

## Contributions and use

This is one repository in the [Fluke](https://github.com/calelamb/fluke) project — a
non-commercial, single-author labor of love for the orcas of the Pacific Northwest.
The source is public so people can see how the app is built and why it makes the
choices it does — including that dorsal-fin matching runs entirely on-device and
ships dormant until a reference catalog is licensed.

**It is not open to outside contributions.** Pull requests and feature issues
aren't being accepted; this is a solo project by design. You're welcome to read
the code and learn from it. No open-source license is attached, so all rights are
reserved — the source is available to understand, not a grant of reuse.
