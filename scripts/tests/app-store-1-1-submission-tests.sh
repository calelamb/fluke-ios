#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
verifier="$repo_root/scripts/verify-app-store-1-1-submission.sh"
package_root="$repo_root/AppStore/1.1"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/fluke-app-store-1-1-tests.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT
failures=0

expect_failure() {
  local name="$1"
  local expected="$2"
  shift 2
  local output
  if output="$("$@" 2>&1)"; then
    printf 'FAIL: %s unexpectedly succeeded\n' "$name" >&2
    failures=$((failures + 1))
  elif [[ "$output" != *"$expected"* ]]; then
    printf 'FAIL: %s missing error %q; got %s\n' "$name" "$expected" "$output" >&2
    failures=$((failures + 1))
  fi
}

expect_success() {
  local name="$1"
  shift
  local output
  if ! output="$("$@" 2>&1)"; then
    printf 'FAIL: %s failed: %s\n' "$name" "$output" >&2
    failures=$((failures + 1))
  fi
}

test -x "$verifier" || {
  echo "FAIL: missing executable App Store 1.1 verifier" >&2
  exit 1
}
test -d "$package_root" || {
  echo "FAIL: missing App Store 1.1 package" >&2
  exit 1
}

expect_failure "checked-in draft has no fabricated screenshots" \
  "requires 1-10 accepted opaque 6.9-inch screenshots" \
  "$verifier" "$package_root"

valid="$test_root/valid"
cp -R "$package_root" "$valid"
mkdir -p "$valid/en-US/screenshots/6.9-inch"
# This existing image is copied only into the temporary test root to exercise
# dimensions and opacity. It is not treated as 1.1 content or submission evidence.
cp "$repo_root/AppStore/1.0/en-US/screenshots/6.9-inch/01-sightings.png" \
  "$valid/en-US/screenshots/6.9-inch/01-sightings.png"
catalog="$test_root/production-catalog-verification.json"
python3 - "$catalog" <<'PY'
import json
import sys

gate_names = (
    "model_package_digest", "catalog_manifest_digest", "input_paths", "package", "catalog",
    "digests", "rights", "embedding_shape", "embedding_norm", "required_reports",
    "parity_samples", "parity_cosine", "closed_set_samples", "top_1", "top_3",
    "open_set_samples", "false_accept",
)
report = {
    "catalogManifestSha256": "b" * 64,
    "gates": [{"name": name, "passed": True} for name in gate_names],
    "modelPackageSha256": "a" * 64,
    "ready": True,
    "schemaVersion": 1,
    "thresholds": {
        "false_accept": 0.05,
        "parity_cosine": 0.999,
        "top_1": 0.65,
        "top_3": 0.8,
    },
}
with open(sys.argv[1], "w", encoding="utf-8") as output:
    json.dump(report, output)
PY

expect_success "staged JSON and gates accept a temporary geometry-opacity fixture" \
  "$verifier" --catalog-verification "$catalog" "$valid"

expect_failure "catalog proof is mandatory" \
  "production catalog verifier output is required" \
  "$verifier" "$valid"

not_ready="$test_root/not-ready.json"
python3 - "$catalog" "$not_ready" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    value = json.load(source)
value["ready"] = False
with open(sys.argv[2], "w", encoding="utf-8") as output:
    json.dump(value, output)
PY
expect_failure "catalog proof must report ready true" \
  "ready must be true" \
  "$verifier" --catalog-verification "$not_ready" "$valid"

bad_digest="$test_root/bad-digest.json"
python3 - "$catalog" "$bad_digest" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    value = json.load(source)
value["catalogManifestSha256"] = "not-a-digest"
with open(sys.argv[2], "w", encoding="utf-8") as output:
    json.dump(value, output)
PY
expect_failure "catalog proof requires real lowercase SHA-256 identities" \
  "catalogManifestSha256 must be a lowercase SHA-256" \
  "$verifier" --catalog-verification "$bad_digest" "$valid"

missing_gate="$test_root/missing-gate.json"
python3 - "$catalog" "$missing_gate" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    value = json.load(source)
value["gates"] = value["gates"][:-1]
with open(sys.argv[2], "w", encoding="utf-8") as output:
    json.dump(value, output)
PY
expect_failure "catalog proof requires the exact mobile release gate set" \
  "gate-name set is incomplete or unexpected" \
  "$verifier" --catalog-verification "$missing_gate" "$valid"

wrong_threshold="$test_root/wrong-threshold.json"
python3 - "$catalog" "$wrong_threshold" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    value = json.load(source)
value["thresholds"]["top_1"] = 0.5
with open(sys.argv[2], "w", encoding="utf-8") as output:
    json.dump(value, output)
PY
expect_failure "catalog proof requires exact mobile release thresholds" \
  "thresholds do not match the mobile release contract" \
  "$verifier" --catalog-verification "$wrong_threshold" "$valid"

bad_url="$test_root/bad-url"
cp -R "$valid" "$bad_url"
python3 - "$bad_url/en-US/metadata.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as source:
    value = json.load(source)
value["supportURL"] = "https://example.invalid/support"
with open(path, "w", encoding="utf-8") as output:
    json.dump(value, output)
PY
expect_failure "metadata requires the live support URL" \
  "supportURL must equal https://fluke-pnw.vercel.app/support" \
  "$verifier" --catalog-verification "$catalog" "$bad_url"

stale_processing_copy="$test_root/stale-processing-copy"
cp -R "$valid" "$stale_processing_copy"
python3 - "$stale_processing_copy/en-US/metadata.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as source:
    value = json.load(source)
for key in ("description", "promotionalText", "whatsNew", "reviewNotes"):
    value[key] = value[key].replace("Camera frames", "Camera input").replace("camera frames", "camera input")
with open(path, "w", encoding="utf-8") as output:
    json.dump(value, output)
PY
expect_failure "metadata retains truthful local-processing copy" \
  "metadata is missing required truthful copy: camera frames" \
  "$verifier" --catalog-verification "$catalog" "$stale_processing_copy"

stale_camera_copy="$test_root/stale-camera-copy"
cp -R "$valid" "$stale_camera_copy"
python3 - "$stale_camera_copy/en-US/metadata.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as source:
    value = json.load(source)
for key in ("description", "promotionalText", "whatsNew", "reviewNotes"):
    value[key] = value[key].replace("live camera", "selected photo").replace("live-camera", "photo")
with open(path, "w", encoding="utf-8") as output:
    json.dump(value, output)
PY
expect_failure "metadata describes the shipping live-camera pipeline" \
  "metadata is missing required truthful copy: live camera" \
  "$verifier" --catalog-verification "$catalog" "$stale_camera_copy"

tracking="$test_root/tracking"
cp -R "$valid" "$tracking"
python3 - "$tracking/app-privacy.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as source:
    value = json.load(source)
value["tracking"] = True
with open(path, "w", encoding="utf-8") as output:
    json.dump(value, output)
PY
expect_failure "privacy declaration rejects tracking" \
  "$.tracking must equal False" \
  "$verifier" --catalog-verification "$catalog" "$tracking"

analytics="$test_root/analytics"
cp -R "$valid" "$analytics"
python3 - "$analytics/app-privacy.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as source:
    value = json.load(source)
value["analytics"] = True
with open(path, "w", encoding="utf-8") as output:
    json.dump(value, output)
PY
expect_failure "privacy declaration rejects analytics" \
  "$.analytics must equal False" \
  "$verifier" --catalog-verification "$catalog" "$analytics"

extra_transmission="$test_root/extra-transmission"
cp -R "$valid" "$extra_transmission"
python3 - "$extra_transmission/app-privacy.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as source:
    value = json.load(source)
value["transmittedOnlyOnExplicitSightingSubmission"].append("device-id")
with open(path, "w", encoding="utf-8") as output:
    json.dump(value, output)
PY
expect_failure "privacy declaration permits only explicit submission fields" \
  "$.transmittedOnlyOnExplicitSightingSubmission must equal" \
  "$verifier" --catalog-verification "$catalog" "$extra_transmission"

missing_local_processing="$test_root/missing-local-processing"
cp -R "$valid" "$missing_local_processing"
python3 - "$missing_local_processing/app-privacy.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as source:
    value = json.load(source)
value["localOnlyProcessing"].remove("embeddings")
with open(path, "w", encoding="utf-8") as output:
    json.dump(value, output)
PY
expect_failure "privacy declaration retains every local-only artifact" \
  "$.localOnlyProcessing must equal" \
  "$verifier" --catalog-verification "$catalog" "$missing_local_processing"

underdeclared_privacy="$test_root/underdeclared-privacy"
cp -R "$valid" "$underdeclared_privacy"
python3 - "$underdeclared_privacy/app-privacy.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as source:
    value = json.load(source)
value["collectedData"] = [entry for entry in value["collectedData"] if entry["dataType"] != "user-id"]
with open(path, "w", encoding="utf-8") as output:
    json.dump(value, output)
PY
expect_failure "privacy declaration cannot underdeclare the six-category shipping manifest" \
  "$.collectedData has too few items" \
  "$verifier" --catalog-verification "$catalog" "$underdeclared_privacy"

wrong_build="$test_root/wrong-build"
cp -R "$valid" "$wrong_build"
python3 - "$wrong_build/en-US/metadata.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as source:
    value = json.load(source)
value["build"] = 3
with open(path, "w", encoding="utf-8") as output:
    json.dump(value, output)
PY
expect_failure "metadata pins version 1.1 build 2" \
  "$.build must equal 2" \
  "$verifier" --catalog-verification "$catalog" "$wrong_build"

over_limit="$test_root/over-limit"
cp -R "$valid" "$over_limit"
python3 - "$over_limit/en-US/metadata.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as source:
    value = json.load(source)
value["subtitle"] = "x" * 31
with open(path, "w", encoding="utf-8") as output:
    json.dump(value, output)
PY
expect_failure "metadata enforces App Store field limits" \
  "$.subtitle exceeds 30 characters" \
  "$verifier" --catalog-verification "$catalog" "$over_limit"

missing_schema_field="$test_root/missing-schema-field"
cp -R "$valid" "$missing_schema_field"
python3 - "$missing_schema_field/en-US/metadata.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as source:
    value = json.load(source)
del value["locale"]
with open(path, "w", encoding="utf-8") as output:
    json.dump(value, output)
PY
expect_failure "metadata is schema complete" \
  "$.locale is required" \
  "$verifier" --catalog-verification "$catalog" "$missing_schema_field"

submitted="$test_root/submitted"
cp -R "$valid" "$submitted"
python3 - "$submitted/review-submission.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as source:
    value = json.load(source)
value["status"] = "submitted"
value["submitted"] = True
value["appStoreConnect"]["submissionId"] = "synthetic-id"
value["submittedAt"] = "2026-07-19T00:00:00Z"
with open(path, "w", encoding="utf-8") as output:
    json.dump(value, output)
PY
expect_failure "receipt remains a null-ID unsubmitted draft" \
  "$.status must equal draft" \
  "$verifier" --catalog-verification "$catalog" "$submitted"

receipt_id="$test_root/receipt-id"
cp -R "$valid" "$receipt_id"
python3 - "$receipt_id/review-submission.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as source:
    value = json.load(source)
value["appStoreConnect"]["submissionId"] = "synthetic-id"
with open(path, "w", encoding="utf-8") as output:
    json.dump(value, output)
PY
expect_failure "draft receipt keeps every App Store Connect ID null" \
  "$.appStoreConnect.submissionId must be null" \
  "$verifier" --catalog-verification "$catalog" "$receipt_id"

receipt_timestamp="$test_root/receipt-timestamp"
cp -R "$valid" "$receipt_timestamp"
python3 - "$receipt_timestamp/review-submission.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as source:
    value = json.load(source)
value["acceptedAt"] = "2026-07-19T00:00:00Z"
with open(path, "w", encoding="utf-8") as output:
    json.dump(value, output)
PY
expect_failure "draft receipt keeps every App Store Connect timestamp null" \
  "$.acceptedAt must be null" \
  "$verifier" --catalog-verification "$catalog" "$receipt_timestamp"

wrong_export="$test_root/wrong-export"
cp -R "$valid" "$wrong_export"
python3 - "$wrong_export/review-submission.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as source:
    value = json.load(source)
value["exportCompliance"]["basis"] = "custom-cryptography"
with open(path, "w", encoding="utf-8") as output:
    json.dump(value, output)
PY
expect_failure "export compliance stays standard exempt HTTPS" \
  "$.exportCompliance.basis must equal standard-https" \
  "$verifier" --catalog-verification "$catalog" "$wrong_export"

missing_screenshots="$test_root/missing-screenshots"
cp -R "$package_root" "$missing_screenshots"
expect_failure "screenshots fail closed while absent" \
  "requires 1-10 accepted opaque 6.9-inch screenshots" \
  "$verifier" --catalog-verification "$catalog" "$missing_screenshots"

if ((failures > 0)); then
  printf '%d App Store 1.1 submission verifier test(s) failed\n' "$failures" >&2
  exit 1
fi

echo "App Store 1.1 submission verifier tests passed"
