# Fluke iOS

Native iOS companion to [Fluke](https://github.com/calelamb/fluke), the Pacific Northwest orca sightings map.

## What this is

A SwiftUI iOS app that pairs with the Fluke website and its standalone API. Five tabs — **Sightings**, **Whales**, **Identify**, **Learn**, **You** — plus a full-screen **Movement Tracks** experience that visualizes a single whale's observed path across years. The app talks directly to the shared Fastify+Prisma+Postgres service; there is no separate iOS server.

## Stack

- **Swift 5.10**, **SwiftUI**, **iOS 17+** deployment target.
- **Three local Swift packages** at `Packages/`:
  - `FlukeKit` — pure-Swift domain layer (API client, models, persistence). No SwiftUI imports.
  - `FlukeUI` — design system (color/font/animation tokens, `DorsalFinShape`, components). SwiftUI-only.
  - `FlukeFeatures` — feature modules, one folder per tab. Depends on Kit + UI.
- **Backend:** [`calelamb/fluke-api`](https://github.com/calelamb/fluke-api), cloned locally as the sibling directory `../fluke-api`.
- **Map basemap:** [MapLibre Native iOS](https://github.com/maplibre/maplibre-gl-native-distribution) with [OpenFreeMap](https://openfreemap.org/) tiles.
- **No third-party HTTP library** — `URLSession` directly.

## Quick start

1. Open [`Fluke.xcworkspace`](./Fluke.xcworkspace) in **Xcode 16+**.
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

The iOS app's default API base is `http://localhost:4000` — set via `FlukeAPIBaseURL` in `App/Fluke/Info.plist`. Override per-build configuration when you need staging/production.

## API contracts

[`fluke-api`](https://github.com/calelamb/fluke-api) is the source of truth for API schemas and deterministic contract fixtures. `FlukeKit` decodes exact copies of the released fixtures so a backend shape change fails in the client test suite before release.

After changing and releasing an API contract, refresh the iOS copies from sibling clones and run both package suites:

```bash
cp ../fluke-api/contracts/fixtures/*.json Packages/FlukeKit/Tests/FlukeKitTests/Fixtures/
for fixture in ../fluke-api/contracts/fixtures/*.json; do
  cmp "$fixture" "Packages/FlukeKit/Tests/FlukeKitTests/Fixtures/$(basename "$fixture")"
done
swift test --package-path Packages/FlukeKit
swift test --package-path Packages/FlukeFeatures
```

Do not hand-edit the copied JSON or add client-only fields. Update the API contract and regenerate its artifacts first, then align the explicit Swift DTOs to the released shape.

## Documentation

| Doc | What it covers |
| --- | --- |
| [`docs/architecture.md`](docs/architecture.md) | Package boundary, dependency rules, how new code lands in the right module |
| [`docs/design-system.md`](docs/design-system.md) | Color/font/animation tokens, `DorsalFinShape`, components reference |
| [`docs/contributing.md`](docs/contributing.md) | TDD workflow, subagent-driven development, code review, branching |
| [`docs/testing.md`](docs/testing.md) | Test strategy, snapshot testing, MockURLProtocol, coverage targets |
| [`docs/build-and-ci.md`](docs/build-and-ci.md) | Local builds, simulator targets, CI workflow, deployment target rationale |

The full design spec lives at [`../fluke/docs/specs/ios-app.md`](../fluke/docs/specs/ios-app.md). Per-milestone implementation plans live at [`../fluke/docs/plans/`](../fluke/docs/plans/).

## Project layout

```
fluke-ios/
├── Fluke.xcworkspace/                  # ← open this in Xcode
├── App/
│   ├── Fluke.xcodeproj/                # iOS app target
│   └── Fluke/
│       ├── FlukeApp.swift              # @main entry
│       ├── ContentView.swift           # gets replaced by RootScene in M-iOS-1
│       ├── Assets.xcassets/            # AppIcon + tinted variants
│       └── Info.plist
├── Packages/
│   ├── FlukeKit/                       # domain layer
│   │   ├── Sources/FlukeKit/
│   │   │   ├── API/                    # APIClient, APIError, Endpoints
│   │   │   ├── Models/                 # Whale, Sighting, Ecotype, …
│   │   │   ├── Services/               # JSONDecoder.fluke
│   │   │   └── Persistence/            # SwiftData @Models (M-iOS-2)
│   │   └── Tests/FlukeKitTests/
│   ├── FlukeUI/                        # design system
│   │   ├── Sources/FlukeUI/
│   │   │   ├── Tokens/                 # Color, Font, Animation
│   │   │   ├── Shapes/                 # DorsalFinShape
│   │   │   ├── Components/             # PlaceholderScreen, …
│   │   │   └── Resources/Fonts/        # Fraunces-Variable.ttf
│   │   └── Tests/FlukeUITests/
│   │       └── __Snapshots__/          # snapshot-testing PNG references
│   └── FlukeFeatures/                  # feature modules
│       └── Sources/FlukeFeatures/
│           ├── Sightings/
│           ├── Whales/
│           ├── Identify/
│           ├── Learn/
│           └── You/
├── docs/                               # ← engineering docs
├── scripts/                            # generators, e.g. placeholder app icon
└── .github/workflows/ci.yml            # GitHub Actions test workflow
```

## Status

Currently shipping **M-iOS-1 (Bootstrap)**. See [`../fluke/docs/plans/README.md`](../fluke/docs/plans/README.md) for the roadmap (M-iOS-1 through M-iOS-7) and [`docs/contributing.md`](docs/contributing.md) for how to pick up the next task.
