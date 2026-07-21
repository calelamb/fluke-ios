# Fluke iOS model card

Fluke 1.1 embeds the exact mobile artifacts certified by the authoritative
`mobile-release-report.json` produced from `fluke-model` commit
`6fe4767cd1c5716a04b655c9eaac4bd745471569` and tree
`fba0c558d30dd4b240e40c931b0ec8e5f4e9d29e`. This document intentionally does not
copy evaluation metrics; the signed app identity binds the authoritative report's model-package and
catalog-manifest digests so one source remains responsible for thresholds, gates, and measured results.

The model compares a dorsal-fin crop with the rights-cleared on-device catalog. Its result is a
ranked suggestion, not a confirmed identity. The UI preserves candidate provenance and confidence,
allows no-match and dismissal, and requires the person using Fluke to select a suggestion before that
selection can become sighting evidence. Live frames, crops, embeddings, the live candidate set, caches,
and drafts remain on device. An explicitly submitted sighting uploads its attached photo and form content
plus the selected catalog ID, similarity score and score semantics, manifest/model/index versions, and
up to five reference-photo IDs. It never uploads the unselected candidate set.

App Store release remains blocked unless the authoritative report says `ready:true`, its digests match
the packaged artifacts, the compiled Core ML model passes archive validation, and the real physical
iPhone report passes `scripts/verify-device-accessibility-report.py`.
