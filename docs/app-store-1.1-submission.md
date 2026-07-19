# App Store 1.1 submission package

The draft package is in `AppStore/1.1`. It targets marketing version 1.1, build 2. Do not
change the Xcode project version from this package workflow.

Run:

```bash
scripts/verify-app-store-1-1-submission.sh \
  --catalog-verification /absolute/path/to/production-catalog-verification.json
```

Pass the exact fluke-model `artifacts/mobile-release/candidate/mobile-release-report.json`.
It must use schema version 1, report `ready:true`, bind lowercase SHA-256 model-package and
catalog-manifest identities, retain the exact mobile threshold contract, and contain the full
required gate-name set with every gate passed. Keep that output outside this draft package;
never create a substitute result. Record its digest and provenance only with the real submission.

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
and content, and attached photo. Optional account use also sends Name and User ID. Export
compliance is standard exempt HTTPS.

Live URLs:

- Marketing: https://fluke-pnw.vercel.app
- Support: https://fluke-pnw.vercel.app/support
- Privacy: https://fluke-pnw.vercel.app/privacy
- API: https://fluke-api.onrender.com
