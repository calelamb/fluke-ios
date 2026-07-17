# App Store release assets

Each numbered directory is an immutable metadata snapshot for that marketing version. The
`en-US/metadata.json` file is the source of truth when entering or automating App Store Connect
metadata. Run `scripts/verify-app-store-release.sh` before archiving.

Fluke targets iPhone only. Apple accepts one to ten iPhone screenshots. Capture the highest
resolution 6.9-inch set so App Store Connect can scale it for smaller displays. Run
`scripts/capture-app-store-screenshots.sh`; it uses the pinned iPhone 17 Pro Max simulator and
exports named XCTest attachments from the result bundle.
