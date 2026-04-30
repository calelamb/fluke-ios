# Fluke iOS

Native iOS companion to [Fluke](../fluke), the Pacific Northwest orca sightings map.

See [`../fluke/docs/specs/ios-app.md`](../fluke/docs/specs/ios-app.md) for the design spec.

## Stack

- Swift 5.10, SwiftUI, iOS 17+
- Three local Swift packages: `FlukeKit` (domain), `FlukeUI` (design system), `FlukeFeatures` (screens)
- Backend: shared with the web at `../fluke/apps/api`

## Setup

1. Open `Fluke.xcworkspace` in Xcode 15.4+.
2. Select the `Fluke` scheme + an iOS 17 simulator.
3. ⌘R to run.

The app talks to a local Fluke API at `http://localhost:4000` by default; start it with `cd ../fluke && pnpm dev`.

## Development

- Tests: `⌘U` in Xcode, or `xcodebuild test -workspace Fluke.xcworkspace -scheme Fluke -destination 'platform=iOS Simulator,name=iPhone 15'` from the command line.
- CI runs the same on every PR.
