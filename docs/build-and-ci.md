# Build and CI

Local builds, simulator targets, deployment target rationale, and the GitHub Actions workflow.

## Local development

### Prerequisites

- macOS 15+ with **Xcode 26.0.1** (`xcodebuild -version` is pinned in CI).
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

The plans were originally written referencing `iPhone 15`. With Xcode 26 / iOS 26, the available simulators include `iPhone 16e`, `iPhone 17`, `iPhone 17 Pro`, `iPhone 17 Pro Max`, and `iPhone Air`. **Use `iPhone 17` for current builds.** CI resolves the exact simulator UDID and waits for `simctl bootstatus` before testing.

If you're on an older Xcode:

| Xcode | Default iPhone simulator |
| --- | --- |
| 26.x | iPhone 17 |
| 16.x | iPhone 16 |
| 15.x | iPhone 15 |
| 14.x | iPhone 14 |

The workflow pins an iPhone 17 on the iOS 26.0 runtime. It does not use `OS=latest`, so hosted-runner drift cannot silently change the test destination.

### Deployment target

The Xcode project and all Swift packages target **iOS 17.0**. The iOS 26 simulator is the verified build environment, not the minimum customer OS.

### Build configurations

The Xcode project ships three configurations: `Debug`, `Staging`, and `Release`. Differences:

- `Debug` — assertions on, no optimization, faster builds.
- `Staging` — release-like behavior pointed at the staging HTTPS API.
- `Release` — assertions off, full optimization, used by App Store builds.

Each configuration inherits an xcconfig in `App/Configuration/`. Debug may use localhost; Staging and Release require a non-local HTTPS API origin and fail closed on missing or unsafe values.

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

We use `macos-15` and explicitly select Xcode 26.0.1. The workflow requires the iOS 26.0.1 runtime and an iPhone 17 simulator before running any tests, resolves its UDID deterministically, waits for boot completion, and disables parallel simulator testing. The app-test step has a 10-minute timeout; simulator diagnostics and the `.xcresult` upload run even after failure.

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
