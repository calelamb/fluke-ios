# Fluke iOS 1.1 build 2 — dormant-matching release runbook

## What this build is

Version 1.1 build 2 from `agent/on-device-ios-release` at `e4d307c`, archived in
**identifier-dormant mode**: FlukeML and the pinned `FlukeEmbedder.mlpackage`
(digest `e784dac7…`) ship in the binary, the Identify tab provides a live
on-device camera framing preview, and matching stays off because no reference
catalog is bundled. Store copy, review notes, and the embedded
`FlukeBuildIdentity.plist` (`identifierMode: dormant`) all state this plainly.

Model provenance: reviewed model commit `6fe4767c…` (worktree
`fluke-model/.worktrees/reviewed-6fe4767`), release candidate at
`fluke-model/.worktrees/on-device-coreml-release/artifacts/mobile-release/candidate`.

## Reproduce the archive

```bash
cd fluke-ios/.worktrees/on-device-ios-release
FLUKE_MODEL_CHECKOUT=…/fluke-model/.worktrees/reviewed-6fe4767 \
FLUKE_MODEL_RELEASE=…/fluke-model/.worktrees/on-device-coreml-release/artifacts/mobile-release/candidate \
FLUKE_IDENTIFIER_MODE=dormant \
xcodebuild archive -project App/Fluke.xcodeproj -scheme Fluke -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/app-store-1.1/Fluke-1.1-2.xcarchive \
  CODE_SIGN_STYLE=Automatic "CODE_SIGN_IDENTITY=Apple Development" DEVELOPMENT_TEAM=86RBV2JZ8F \
  PROVISIONING_PROFILE_SPECIFIER= ENABLE_USER_SCRIPT_SANDBOXING=NO -allowProvisioningUpdates
```

## Upload (signs with cloud Apple Distribution + uploads to App Store Connect)

`App/ExportOptions.plist` has `method: app-store-connect`, `destination: upload`,
`signingStyle: automatic` — the same flow codex used for the 1.0 build 1
TestFlight upload:

```bash
xcodebuild -exportArchive -archivePath build/app-store-1.1/Fluke-1.1-2.xcarchive \
  -exportOptionsPlist App/ExportOptions.plist -allowProvisioningUpdates
```

Fallback if the Xcode session can't upload: Transporter/altool with the ASC key
(file only — never print it):

```bash
API_PRIVATE_KEYS_DIR="…/fluke-secrets" xcrun altool --upload-app --type ios \
  --file <ipa> --apiKey ASA2L2U7D4 --apiIssuer <ISSUER_ID>
```

## After upload processes (App Store Connect)

1. appstoreconnect.apple.com → My Apps → Fluke → iOS 1.1.
2. Paste the copy from `AppStore/1.1/en-US/metadata.json` (subtitle, description,
   keywords, promo, what's new, review notes).
3. Screenshots: capture via `scripts/capture-app-store-screenshots.sh` with the
   same model env vars (7 canonical 6.9-inch shots + provenance manifest).
4. App Privacy answers: mirror `AppStore/1.1/app-privacy.json`.
5. Export compliance: `ITSAppUsesNonExemptEncryption=false` is already in the
   Info.plist — no prompt expected.
6. Select the processed build 2 → Add for Review → Submit.
7. Record submission ID/date/SHA in `AppStore/1.1/review-submission.json`.

## Still gated (deliberately)

- **Live matching** stays off until a rights-cleared catalog passes the model
  release verifier (`ready:true`). Researched 2026-07-19: there is NO
  public-domain path for SRKW/Bigg's imagery — the CWR catalog is contractor
  copyright, DFO catalogs are Canadian Crown copyright, NOAA drone imagery is
  credited to non-federal researchers. The only rights-clean federal sets
  (CC0 Gulf of Mexico, PD 1997 Alaska B&W) are wrong populations, useful for
  pretraining only. Licensing grants (CWR / Orca Network / DFO / SR3) are the
  critical path; the drafted letters in `fluke/docs/outreach/` cite the
  retired demo and need a rewrite before sending.
- The full `verify-app-store-1-1-submission.sh` packaging verifier still
  expects the identifier-live evidence set (screenshot provenance, complete
  physical-device report). Its dormant-mode variant is intentionally not
  implemented; the review-notes and copy gates above were updated instead.
- Physical-device verification (`AppStore/1.1/evidence/…`) should still be run
  on the iPhone 15 Pro before wide release.
