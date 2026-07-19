# App Store 1.1 submission package

The draft package is in `AppStore/1.1`. It targets marketing version 1.1, build 2. The
verifier reads the Release build settings for the shipping `Fluke` scheme and fails unless
`MARKETING_VERSION` is 1.1 and `CURRENT_PROJECT_VERSION` is 2. The checked-in project is
still 1.0 build 1, so the draft cannot pass until the release owner makes that separate
shipping-target change.

Run:

```bash
scripts/verify-app-store-1-1-submission.sh \
  /absolute/path/to/reviewed/fluke-model-checkout \
  /absolute/path/to/artifacts/mobile-release/candidate \
  /absolute/path/to/Fluke.xcarchive
```

The executable keeps its historical `.sh` name but is implemented in Python. It accepts exactly
three positional production inputs and has no test, fixture, environment, build-settings, app-root,
or membership override. It constructs a minimal subprocess environment, so ambient `PATH` and
`XCODE_XCCONFIG_FILE` values cannot change release verification.

The fluke-model checkout is authenticated to source commit
`6fe4767cd1c5716a04b655c9eaac4bd745471569` and reviewed tree
`fba0c558d30dd4b240e40c931b0ec8e5f4e9d29e`. The verifier also pins the SHA-256 identities of
`scripts/verify_mobile_release.py`, `uv.lock`, and `pyproject.toml`, and rejects dirty or untracked
files under the authoritative verifier inputs. Using an absolute regular `uv` executable, the
pinned executable SHA-256
`51f0ae3c531a124727fa39e16e8599f2e371e427822a4aa92ebf667b52548b43`, the pinned lockfile,
offline mode, and a clean environment, it invokes `scripts/verify_mobile_release.py`
fresh against the supplied release directory. That invocation overwrites or produces
`mobile-release-report.json` and must exit zero. Only then does the App Store verifier validate
the report schema and independently recompute the Core ML package-tree and catalog-manifest
digests. A hand-authored `ready:true` report without the rights, export, catalog, parity, and
evaluation evidence inspected by the authoritative verifier fails.

The third input must be the actual `.xcarchive`, not a source tree or a claimed membership list.
The verifier requires version 1.1, build 2, and bundle `app.fluke.Fluke` in both archive and app
Info.plists. It compares these archived catalog resources byte-for-byte with the verified release:

- `Products/Applications/Fluke.app/IdentifierCatalog/manifest.json`
- `Products/Applications/Fluke.app/IdentifierCatalog/metadata.json`
- `Products/Applications/Fluke.app/IdentifierCatalog/references.f16`

The archive must contain exactly one compiled `FlukeEmbedder.mlmodelc`. The verifier loads it
with Core ML, enforces the `pixels` float32 `[1,3,224,224]` input and `embedding` float32
`[1,384]` output, performs a prediction, and requires a finite unit-normalized embedding. Existing
archive privacy, signing, bundle, and deployment validators also run.

`FlukeBuildIdentity.plist` at the archive root must exactly record schema version 1, the current
clean iOS source commit and tree, the pinned model commit and tree, version/build, and the verified
model-package and catalog-manifest digests. Direct parsing of the Fluke target's Release
configuration and sanitized `xcodebuild -showBuildSettings` must independently agree on 1.1/2.
Filesystem-synchronized target membership is only a supplemental check; every exception set for
the Fluke target is inspected for hidden identification resources.

The verifier remains blocked until `AppStore/1.1/en-US/screenshots/6.9-inch` contains one to
ten real, App Store-accepted, opaque 6.9-inch screenshots. Do not copy the 1.0 screenshots into
the production 1.1 package merely to clear the gate: exact 1.0 screenshot digests are denied.
Package JSON, schemas, screenshots, model/release inputs, catalog files, and archive contents must
all be regular no-follow paths; symbolic-link components fail closed.

`review-submission.json` is a draft, not an App Store Connect receipt. Its status remains
`draft`, `submitted` remains false, and every App Store Connect ID and submission timestamp
remains null until a real submission succeeds. After that external event, record the real IDs
and timestamps in a separate reviewed receipt change.

The privacy draft matches the six categories in the shipping privacy manifest. Camera frames,
photo crops, embeddings, match candidates, caches, and drafts stay on device. Fluke has no
analytics or tracking. Explicit sighting submission sends its contact email, user-chosen location
and content, and attached photo. Optional account use separately sends Name, account email, and
User ID. Sign in with Apple separately sends its identity token and one-use authorization code
for authentication. Export compliance is standard exempt HTTPS.

Identification copy describes the shipping live-camera flow as dorsal-fin matching for orca
individuals. It does not call the camera target a fluke or imply selected-photo identification.

Live URLs:

- Marketing: https://fluke-pnw.vercel.app
- Support: https://fluke-pnw.vercel.app/support
- Privacy: https://fluke-pnw.vercel.app/privacy
- API: https://fluke-api.onrender.com
