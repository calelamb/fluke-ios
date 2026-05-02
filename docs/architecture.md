# Architecture

How the iOS app is organized, what goes where, and the dependency rules that keep it maintainable.

The full design rationale lives in [`../../fluke/docs/specs/ios-app.md`](../../fluke/docs/specs/ios-app.md). This doc is the engineering-side reference.

## Three packages, one app target

```
┌────────────────────────────────────┐
│  App (Fluke.xcodeproj)             │
│  - FlukeApp.swift @main            │
│  - RootScene.swift  (tab shell)    │
│  - AppEnvironment.swift  (DI)      │
└─────────────┬──────────────────────┘
              │ imports
              ▼
┌────────────────────────────────────┐
│  FlukeFeatures                     │
│  - Sightings/, Whales/, Identify/, │
│    Learn/, You/, Submit/,          │
│    MovementTrack/                  │
└────┬───────────────────────────┬───┘
     │ imports                   │ imports
     ▼                           ▼
┌──────────────┐         ┌──────────────────┐
│  FlukeKit    │         │  FlukeUI         │
│  (domain)    │         │  (design system) │
│              │         │                  │
│  - API/      │         │  - Tokens/       │
│  - Models/   │         │  - Shapes/       │
│  - Services/ │         │  - Components/   │
│  - Persistence/        │  - Resources/    │
│  - Repositories/       │                  │
└──────────────┘         └──────────────────┘
```

### Dependency rules (enforced by review)

1. **`FlukeKit` depends on nothing project-internal.** No SwiftUI imports. No FlukeUI types. No feature code. Just Swift, Foundation, SwiftData, system frameworks.
2. **`FlukeUI` imports `SwiftUI` but no domain.** No `Whale`, `Sighting`, `APIClient` references. The design system doesn't know what an orca is.
3. **`FlukeFeatures` depends on Kit + UI; never on itself.** A feature module (say `Sightings/`) imports `FlukeKit` and `FlukeUI` but never imports another feature folder. If two features need to share something, it goes in Kit or UI.
4. **`App/` depends on FlukeFeatures (and transitively on Kit + UI).** The App target is small — entry point, root scene, environment plumbing. All real screens live in feature modules.

When this falls down: if you find yourself wanting to import one feature from another, the shared piece probably belongs in `FlukeKit` (if domain) or `FlukeUI` (if presentation). Refactor before adding the cross-feature import.

## Why three packages

### Build isolation

Each package builds and tests independently. `cd Packages/FlukeKit && swift test` runs without touching the App target or the other packages. CI matrix-tests them in parallel — three jobs running concurrently.

### Compile-time safety against architectural drift

Swift's package boundaries enforce visibility. A feature module physically cannot reach into another feature's internals — different modules. An accidental `import OtherFeature` breaks the build.

### LLM-friendly file scope

Each package is small enough that an agent (or human) can hold its full surface area in context at once. A feature folder is typically 4-8 files; a token file is one screen of code. This is a deliberate optimization: large files become brittle under agentic editing, so the architecture is built around small focused units.

## Where new code goes

| You're adding… | It goes in… |
| --- | --- |
| A new screen | `FlukeFeatures/Sources/FlukeFeatures/<feature>/` |
| A new SwiftUI component reused across features | `FlukeUI/Sources/FlukeUI/Components/` |
| A new design token | `FlukeUI/Sources/FlukeUI/Tokens/` |
| A new shape primitive | `FlukeUI/Sources/FlukeUI/Shapes/` |
| A new font / asset | `FlukeUI/Sources/FlukeUI/Resources/` |
| An API endpoint constant | `FlukeKit/Sources/FlukeKit/API/Endpoints.swift` |
| A new HTTP request method on the client | `FlukeKit/Sources/FlukeKit/API/APIClient.swift` |
| A new domain model (DTO) | `FlukeKit/Sources/FlukeKit/Models/` |
| A repository (API + cache) | `FlukeKit/Sources/FlukeKit/Repositories/` |
| A SwiftData `@Model` | `FlukeKit/Sources/FlukeKit/Persistence/` |
| A service (auth, identify, submit) | `FlukeKit/Sources/FlukeKit/Services/` |
| A new tab | `FlukeFeatures/.../<NewTab>/` + wire in `App/Fluke/RootScene.swift` |
| A view model | Co-located with its view in the feature folder |

## Data layer

### API client

`FlukeKit/API/APIClient.swift` wraps `URLSession`. It:

- Reads/writes cookies via `URLSession.configuration.httpCookieStorage` automatically — matches the cookie-based auth the web's API already uses for admin (and observer, once M-iOS-3 lands).
- Decodes responses with `JSONDecoder.fluke` (handles Prisma's milliseconds-precision ISO-8601 dates and string-encoded `Decimal` lat/lng).
- Surfaces errors as the typed `APIError` enum — `.network`, `.unauthorized`, `.server(status, body)`, `.decoding(typeName)`, `.unknown`.
- Has a single retry policy: transient network errors get one retry; 4xx never retries.

Tests live at `FlukeKitTests/APIClientTests.swift` and use `MockURLProtocol` (a URLProtocol subclass that hijacks requests).

### Repositories

A repository owns a single domain entity's API + cache round-trip. Pattern: fetch from API, write to cache, return DTOs. On API failure, return whatever the cache has.

Land in `FlukeKit/Repositories/` starting in M-iOS-2. Examples:

- `WhalesRepository` — `fetchAll() async throws -> [Whale]` + `find(byId:)` + `fetchTrack(whaleId:)`
- `SightingsRepository` — `fetchApproved()` + `fetchMine()` (signed-in)
- `SubmissionsRepository` — `submit(payload:photoBytes:)` + `replayQueued()` for offline support

### Persistence (SwiftData)

`@Model` classes in `FlukeKit/Persistence/`. Stored locally on device; mirror API DTOs but include offline-only fields like `cachedAt`, `viewedAt`, `submissionState`. Photo binaries are NOT stored in SwiftData (binary blobs are an anti-pattern there) — they live in `Documents/queued-photos/<uuid>.jpg`, referenced by ID.

The `ModelContainer` is constructed once in `AppEnvironment` and shared via SwiftUI environment.

### Auth

`AuthService` in `FlukeKit/Auth/` exchanges Apple identity tokens for the API's HTTP-only cookie. The cookie is persisted automatically by `URLSession.configuration.httpCookieStorage`. An `AuthSession` `@Observable` lives in the App target (not a package) and broadcasts the current user state to the SwiftUI tree via environment. Lands in M-iOS-3.

## UI layer

### Design tokens

In `FlukeUI/Tokens/`:

- `Color+Fluke.swift` — 7 semantic colors (`bone`, `fog`, `mist`, `tide`, `deep`, `abyss`, `ember`), each a port of the web's `tokens.css`.
- `Font+Fluke.swift` — Fraunces variable font (display) + SF Pro Text (body) tokens, plus `FlukeUIFontRegistration.registerIfNeeded()`.
- `Animation+Fluke.swift` — `flukeSpring`, `flukeFast`, `flukeBase`, `flukeSlow` ports of the web's motion tokens.

### Shapes

In `FlukeUI/Shapes/`:

- `DorsalFinShape` — the canonical Fluke glyph as a SwiftUI `Shape`. Used as tab icon, map markers, empty-state glyph, app icon. **One source of truth** for the brand mark across every surface.

### Components

In `FlukeUI/Components/`:

- `PlaceholderScreen` — empty-state scaffold (M-iOS-1 placeholders use this).
- `EcotypeBadge`, `MapMarker`, `SearchField`, `FilterChip`, `PrimaryButton`, `SecondaryButton`, `FormField`, `QueueBadge`, `DisclaimerRibbon`, `ConfidenceBar` — landing in M-iOS-2 through M-iOS-6.
- `Haptics` — sparing helper for `.impact(.soft)`/`.notification(.success)`. Lands in M-iOS-7.

## App target

### `FlukeApp.swift`

The `@main` entry. Constructs `AppEnvironment` (and `AuthSession`, `SubmissionReplayer` when those land), injects them into the SwiftUI environment, and presents `RootScene`.

### `RootScene.swift`

The 5-tab `TabView`. Each tab roots its own `NavigationStack`. The Submit `+` button opens a sheet from the Sightings nav bar; it's not a dedicated tab (it's an action, not a destination).

### `AppEnvironment.swift`

Top-level dependency container. Holds singletons whose lifetime is the app process: `APIClient`, `ModelContainer`, repositories, `AuthService`, `NetworkMonitor`. Injected into views via SwiftUI's `@Environment`.

## Out-of-scope (deferred)

- **On-device ML**: Photo identification runs server-side via Modal. This isn't an architectural lock-in — swapping to Core ML is contained to `FlukeKit/Services/IdentifyService.swift`. It's just not a v1 priority. See spec § Decisions for the reasoning.
- **Push notifications**: Phase 2 of the spec.
- **iPad-tuned layout**: Phone-first.
- **Apple Watch / widgets**: Out of scope.

## Visual reference

For a visual flow of how user actions move through the layers (UI → ViewModel → Repository → APIClient → API), see [`design-system.md`](design-system.md) for the design-system view and [`testing.md`](testing.md) for how each layer is tested.
