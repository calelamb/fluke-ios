# Build and CI

Local builds, simulator targets, deployment target rationale, and the GitHub Actions workflow.

## Local development

### Prerequisites

- macOS 15+ with **Xcode 26.0.1** (`xcodebuild -version` is pinned in CI).
- Command Line Tools (`xcode-select --install`).
- The iOS 26.0.1 simulator runtime installed through Xcode → Settings → Platforms.
- For Swift package work: nothing else — `swift` ships with Xcode.
- For the standalone API alongside the app: Node 22.17.0 and pnpm 10.33.0, matching [`../../fluke-api/package.json`](../../fluke-api/package.json).

### Day-to-day

```bash
# Open the workspace
open Fluke.xcworkspace

# Or run from the command line
xcodebuild build \
  -workspace Fluke.xcworkspace \
  -scheme Fluke \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.0.1' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

`CODE_SIGNING_ALLOWED=NO` is required for the repository's portable simulator and unsigned-archive verification. Developer-device and App Store builds require an Apple team, signing certificate, and provisioning profile supplied outside the repository.

### Simulator destination

The plans were originally written referencing `iPhone 15`. With Xcode 26 / iOS 26, the available simulators include `iPhone 16e`, `iPhone 17`, `iPhone 17 Pro`, `iPhone 17 Pro Max`, and `iPhone Air`. **Use `iPhone 17` for current builds.** CI resolves the exact simulator UDID and waits for `simctl bootstatus` before testing.

The workflow pins an iPhone 17 on the exact iOS 26.0.1 runtime, so hosted-runner drift cannot silently change the test destination. Simulator boot is bounded to 180 seconds, performs at most one safe shutdown/reboot recovery, and then fails with the resolved device list instead of consuming the full CI timeout. The entire simulator-preparation step has a five-minute ceiling.

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
all package tests + FlukeKit and selected FlukeFeatures logic coverage gates
    ↓
meaningful app tests + 80% app line-coverage gate
    ↓
Debug build + Release build
    ↓
unsigned generic iPhone archive + metadata validation
```

The workflow uploads the app `.xcresult`, the machine-readable app coverage report, all package coverage reports, and validated archive metadata on every run. FlukeFeatures' 80% gate is limited to named testable logic files; SwiftUI view bodies are validated through render, UI, and build checks rather than included in that numeric claim. Production deployment and signing remain separate and require an exact green SHA.

### Runner choice

We use `macos-15` and explicitly select Xcode 26.0.1. The workflow requires the iOS 26.0.1 runtime and an iPhone 17 simulator before running any tests, resolves its UDID deterministically, waits for boot completion, and disables parallel simulator testing. The app-test step has a 10-minute timeout; simulator diagnostics and the `.xcresult` upload run even after failure.

`macos-14` was the previous default but lacks iOS 18+ simulators by default. `macos-26` (when GitHub adds it) will be the natural target once it's GA.

### Caching

We don't cache `.build/` directories yet — the package tests are fast enough that the cache overhead doesn't pay off. If build times grow past ~3 minutes total, add `actions/cache` keyed on `Package.resolved`.

## TestFlight and App Store

The checked-in workflow proves source, tests, coverage, real Release A feature wiring, Release compilation, and unsigned archive metadata. It intentionally does not claim a TestFlight upload: this repository currently has no signing credentials or upload workflow.

`Release.xcconfig` is pinned to the certified production origin `https://fluke-api.onrender.com`. Before submission, confirm that origin remains healthy, review the bundled opaque app icon at App Store sizes, configure the Apple developer team and distribution provisioning, create or confirm the App Store Connect record and metadata, and archive/upload the exact green SHA with signing enabled. The unsigned CI archive is verification evidence, not a distributable artifact.

## Common build issues

### "No such module FlukeKit"

The App target isn't linked against the package. Open `Fluke.xcworkspace`, select `Fluke` target → General → "Frameworks, Libraries, and Embedded Content" → ensure `FlukeKit`, `FlukeUI`, `FlukeFeatures` are listed (with "Do Not Embed"). If any product is missing, restore the package-product references in `App/Fluke.xcodeproj` and rerun the Release A boundary verifier.

### "Couldn't find file `icon-1024.png`"

The Asset Catalog references the opaque brand icon at `App/Fluke/Assets.xcassets/AppIcon.appiconset/icon-1024.png`. If it's missing, regenerate:

```bash
swift scripts/generate-app-icon.swift
```

Review the bundled icon at App Store sizes before submission; asset validation is part of the signed archive handoff.

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
