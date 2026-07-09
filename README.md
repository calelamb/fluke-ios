# Fluke iOS

Native iOS companion to [Fluke](../fluke), the Pacific Northwest orca sightings map.

## What this is

A SwiftUI iOS app that pairs with the existing Fluke web/API. Five tabs — **Sightings**, **Whales**, **Identify**, **Learn**, **You** — plus a full-screen **Movement Tracks** experience that visualizes a single whale's observed path across years. The app talks to the same Fastify+Prisma+Postgres backend the web app uses; there is no separate iOS server.

## Stack

- **Swift 5.10**, **SwiftUI**, **iOS 17+** deployment target.
- **Three local Swift packages** at `Packages/`:
  - `FlukeKit` — pure-Swift domain layer (API client, models, persistence). No SwiftUI imports.
  - `FlukeUI` — design system (color/font/animation tokens, `DorsalFinShape`, components). SwiftUI-only.
  - `FlukeFeatures` — feature modules, one folder per tab. Depends on Kit + UI.
- **Backend:** shared with the web at `../fluke/apps/api`.
- **Map basemap:** [MapLibre Native iOS](https://github.com/maplibre/maplibre-gl-native-distribution) with [OpenFreeMap](https://openfreemap.org/) tiles.
- **No third-party HTTP library** — `URLSession` directly.

## Quick start

1. Open [`Fluke.xcworkspace`](./Fluke.xcworkspace) in **Xcode 16+**.
2. Pick an iPhone 17 (or newer) simulator from the scheme dropdown.
3. ⌘R.

To talk to the local API:

```bash
cd ../fluke
pnpm install
pnpm db:seed   # populates whales + sightings
pnpm dev       # API runs on http://localhost:4000
```

The iOS app's default API base is `http://localhost:4000` — set via `FlukeAPIBaseURL` in `App/Fluke/Info.plist`. Override per-build configuration when you need staging/production.

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

**M-iOS-1 (Bootstrap) is incomplete** — packages and Atlas exist, but the App target is still the Xcode template and is not linked to the packages. For a prioritized gap list toward a working, App Store–ready product, see [`docs/app-store-readiness-triage.md`](docs/app-store-readiness-triage.md). Roadmap context: [`../fluke/docs/plans/README.md`](../fluke/docs/plans/README.md) (M-iOS-1 through M-iOS-7).
