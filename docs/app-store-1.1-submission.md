# App Store 1.1 submission package

The draft package is in `AppStore/1.1`. It targets marketing version 1.1, build 2. The
verifier reads the Release build settings for the shipping `Fluke` scheme and fails unless
`MARKETING_VERSION` is 1.1 and `CURRENT_PROJECT_VERSION` is 2. The checked-in project is
still 1.0 build 1, so the draft cannot pass until the release owner makes that separate
shipping-target change.

Run:

```bash
scripts/verify-app-store-1-1-submission.sh \
  --mobile-release-directory /absolute/path/to/artifacts/mobile-release/candidate
```

Pass the actual fluke-model mobile release directory used to stage the app, not a detached JSON
copy. The verifier reads its `mobile-release-report.json`, enforces the exact schema emitted by
`fluke_model.mobile_release.report_payload` (including ordered gates, observations,
requirements, details, counts, metrics, and thresholds), and independently recomputes the
Core ML package-tree digest and catalog-manifest digest. This exact field contract and digest
algorithm are the verifier's provenance boundary; a hand-authored `ready:true` document cannot
substitute for the model repository's release verifier output.

The verifier then compares that release directory byte-for-byte with the identification
resources intended for the shipping app:

- `App/Fluke/Models/FlukeEmbedder.mlpackage`
- `App/Fluke/IdentifierCatalog/manifest.json`
- `App/Fluke/IdentifierCatalog/metadata.json`
- `App/Fluke/IdentifierCatalog/references.f16`

It also verifies that the filesystem-synchronized `App/Fluke` root belongs to the `Fluke`
target's Resources phase. The checked-in app has no `IdentifierCatalog` directory yet, so an
external release report alone cannot clear the submission gate. The fixture overrides in the
focused test suite are rejected unless `FLUKE_APP_STORE_TESTING=true`; they are not production
verification inputs.

The verifier remains blocked until `AppStore/1.1/en-US/screenshots/6.9-inch` contains one to
ten real, App Store-accepted, opaque 6.9-inch screenshots. Do not copy the 1.0 screenshots into
the production 1.1 package merely to clear the gate.

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
