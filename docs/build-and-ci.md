# Build and CI

Local builds, simulator targets, deployment target rationale, and the GitHub Actions workflow.

## Local development

### Prerequisites

- macOS 14+ with **Xcode 16+** (`xcodebuild -version` should show Xcode 16.x).
- Command Line Tools (`xcode-select --install`).
- An iOS 17+ simulator (Xcode → Settings → Platforms — iOS 26 is bundled with Xcode 16, iOS 17/18 are downloadable).
- For Swift package work: nothing else — `swift` ships with Xcode.
- For the full Fluke stack (running the API alongside): pnpm 9+, Node 20+ (see [`../../fluke/README.md`](../../fluke/README.md)).

### Day-to-day

```bash
# Open the workspace
open Fluke.xcworkspace

# Or run from the command line
xcodebuild build \
  -workspace Fluke.xcworkspace \
  -scheme Fluke \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

`CODE_SIGNING_ALLOWED=NO` is required because we don't have a signing identity configured for local builds (M-iOS-7 sets up signing). For development against the simulator, no code signing is needed.

### Simulator destination

The plans were originally written referencing `iPhone 15`. With Xcode 16 / iOS 26 (current as of 2026-04), the available simulators are `iPhone 16e`, `iPhone 17`, `iPhone 17 Pro`, `iPhone 17 Pro Max`, `iPhone Air`, plus iPad models. **Use `iPhone 17` for current builds.**

If you're on an older Xcode:

| Xcode | Default iPhone simulator |
| --- | --- |
| 16+ | iPhone 17 |
| 15.x | iPhone 15 |
| 14.x | iPhone 14 |

The workflow file uses `name=iPhone 16,OS=latest` — broadest compatibility across GitHub Actions hosted runners and local machines.

### Deployment target

The Xcode project's deployment target is currently **iOS 26.0** (Xcode 16 default). The original plan called for **iOS 17.0** to support a wider range of devices. Lowering the deployment target to iOS 17 is non-trivial today because:

- M-iOS-1 already uses `Color.resolve(in:)` (iOS 17+) — fine.
- iOS 26 introduces `@Observable` improvements we may rely on later.
- The newer Foundation Models framework on iOS 26+ will be relevant for the Identify feature long-term.

**Decision (deferred):** keep iOS 26 deployment target through M-iOS-1 through M-iOS-6. Re-evaluate at M-iOS-7 polish — if shipping to older devices is important for App Store reach, lower the target there. The Swift packages target iOS 17+ so they remain reusable on older devices regardless.

### Build configurations

The Xcode project ships two configurations: `Debug` and `Release`. Differences:

- `Debug` — assertions on, no optimization, faster builds.
- `Release` — assertions off, full optimization, used by App Store builds.

The `FlukeAPIBaseURL` value in `Info.plist` defaults to `http://localhost:4000`. To override for staging/production builds, edit `Info.plist` for the target build configuration. M-iOS-7 sets up multi-environment plist variants; for now, swap the value as needed and revert before committing.

## CI workflow

Lives at [`.github/workflows/ci.yml`](../.github/workflows/ci.yml). Triggers on every push to `main` and every PR.

### Verification lane

```
canonical fixture manifest + verifier self-tests
    ↓
all package tests + package coverage reports
    ↓
meaningful app tests + 80% app line-coverage gate
    ↓
Debug build + Release build
    ↓
unsigned generic iPhone archive + metadata validation
```

The workflow uploads the app `.xcresult`, the machine-readable app coverage report, all package coverage reports, and validated archive metadata on every run. Production deployment and signing remain separate and require an exact green SHA.

### Runner choice

We use `macos-15` and explicitly select Xcode 26.0.1. The workflow requires the iOS 26.0.1 runtime and an iPhone 17 simulator before running any tests, so runner-image drift fails at the toolchain gate instead of changing render or build behavior silently.

`macos-14` was the previous default but lacks iOS 18+ simulators by default. `macos-26` (when GitHub adds it) will be the natural target once it's GA.

### Caching

We don't cache `.build/` directories yet — the package tests are fast enough that the cache overhead doesn't pay off. If build times grow past ~3 minutes total, add `actions/cache` keyed on `Package.resolved`.

## TestFlight and App Store

M-iOS-7 brings:

- **fastlane** for TestFlight uploads (`fastlane beta`).
- **GitHub Actions** workflow at `.github/workflows/testflight.yml` triggered on `git tag v*`.
- **App Store Connect** record creation.

Until then, all builds stay on the simulator. There's no point setting up signing if no one's installing on a real device yet.

The fastlane lane definition + secrets list lives in [`../../fluke/docs/plans/m-ios-7-polish-app-store.md`](../../fluke/docs/plans/m-ios-7-polish-app-store.md) Tasks 8 and 9.

## Common build issues

### "No such module FlukeKit"

The App target isn't linked against the package. Open `Fluke.xcworkspace`, select `Fluke` target → General → "Frameworks, Libraries, and Embedded Content" → ensure `FlukeKit`, `FlukeUI`, `FlukeFeatures` are listed (with "Do Not Embed"). If they're missing, this is a Task 6 wiring issue — see [`m-ios-1-bootstrap.md`](../../fluke/docs/plans/m-ios-1-bootstrap.md) Task 6.

### "Couldn't find file `icon-1024.png`"

The Asset Catalog references the placeholder icon at `App/Fluke/Assets.xcassets/AppIcon.appiconset/icon-1024.png`. If it's missing, regenerate:

```bash
swift scripts/generate-placeholder-icon.swift
```

The final icon ships in M-iOS-7.

### "Unable to find a device matching the destination"

Your `xcodebuild` `-destination` flag references a simulator that's not installed. Run:

```bash
xcrun simctl list devices available | grep iPhone
```

…to see what's available on your machine, and adjust the destination accordingly.

### Snapshot test "No reference was found on disk"

This is the snapshot library's first-run behavior — it just recorded a new reference. Run the test command again; it should pass on the second run.

If the recorded image looks wrong, delete `Packages/FlukeUI/Tests/FlukeUITests/__Snapshots__/<TestClass>/<TestName>.1.png` and re-record.

### "[Fluke] Font registration: …"

This is the `FlukeUIFontRegistration` warning when CoreText reports a font can't be registered (typically because it's already registered). Safe to ignore — it's a warning, not an error.

### Xcode index/build cache acting weird

```bash
# Nuke derived data
rm -rf ~/Library/Developer/Xcode/DerivedData/Fluke-*

# Then re-open Xcode and build
```

This is rarely necessary but bails you out of "Xcode says everything's fine but the build keeps failing" loops.

## Performance baseline

The current per-task expectation:

| Action | Time |
| --- | --- |
| `swift test` (one package, cached) | <1s |
| `swift test` (one package, cold) | ~30s (resolves deps + builds) |
| `xcodebuild build` (Fluke, cached) | ~2-5s |
| `xcodebuild build` (Fluke, cold) | ~30-60s |
| `xcodebuild test` full suite (warm) | ~30-60s (mostly UI test launch) |
| CI run (all jobs) | ~5-7 minutes |

If a build starts taking 2x what it used to, something regressed — investigate before committing more to it.
