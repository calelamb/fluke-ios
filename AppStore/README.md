# App Store release assets

Each numbered directory is an immutable metadata snapshot for that marketing version. The
`en-US/metadata.json` file is the source of truth when entering or automating App Store Connect
metadata. Run `scripts/verify-app-store-release.sh` before archiving.

Fluke targets iPhone only. Apple accepts one to ten iPhone screenshots. Capture the highest
resolution 6.9-inch set so App Store Connect can scale it for smaller displays. Run
`scripts/capture-app-store-screenshots.sh`; it uses the pinned iPhone 17 Pro Max simulator and
exports named XCTest attachments from the result bundle.

The 6.9-inch launch set is deterministic and must contain exactly these seven files:

1. `01-sightings.png`
2. `02-whales.png`
3. `03-submit.png`
4. `04-identify.png`
5. `05-atlas.png`
6. `06-you.png`
7. `07-learn.png`

The capture script builds the Release configuration with the screenshot-only XCTest fixture
condition, exports those attachments, and runs the screenshot verifier before replacing the
versioned set. Do not rename, omit, or add files without updating the capture test and verifier
together.
