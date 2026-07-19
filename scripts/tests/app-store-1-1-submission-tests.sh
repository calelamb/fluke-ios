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
build_settings="$test_root/build-settings.txt"
cat > "$build_settings" <<'SETTINGS'
    TARGET_NAME = Fluke
    PRODUCT_BUNDLE_IDENTIFIER = app.fluke.Fluke
    MARKETING_VERSION = 1.1
    CURRENT_PROJECT_VERSION = 2
SETTINGS
export FLUKE_APP_STORE_TESTING=true

release_dir="$test_root/mobile-release"
mkdir -p "$release_dir/FlukeEmbedder.mlpackage/Data" "$release_dir/catalog"
printf 'model artifact fixture\n' > "$release_dir/FlukeEmbedder.mlpackage/Data/model.bin"
printf '{"catalog":"fixture"}\n' > "$release_dir/catalog/manifest.json"
printf '{"individuals":[]}\n' > "$release_dir/catalog/metadata.json"
printf 'vector fixture\n' > "$release_dir/catalog/references.f16"
shipping_resources="$test_root/shipping-resources"
mkdir -p "$shipping_resources/Models" "$shipping_resources/IdentifierCatalog"
cp -R "$release_dir/FlukeEmbedder.mlpackage" "$shipping_resources/Models/FlukeEmbedder.mlpackage"
cp "$release_dir/catalog/manifest.json" "$release_dir/catalog/metadata.json" \
  "$release_dir/catalog/references.f16" "$shipping_resources/IdentifierCatalog/"
membership_fixture="$test_root/project-membership.txt"
cat > "$membership_fixture" <<'MEMBERSHIP'
TARGET_NAME=Fluke
SYNCHRONIZED_RESOURCE_ROOT=App/Fluke
RESOURCE=Models/FlukeEmbedder.mlpackage
RESOURCE=IdentifierCatalog/manifest.json
RESOURCE=IdentifierCatalog/metadata.json
RESOURCE=IdentifierCatalog/references.f16
MEMBERSHIP
catalog="$release_dir/mobile-release-report.json"
python3 - "$release_dir" "$catalog" <<'PY'
import hashlib
import json
import pathlib
import sys

release = pathlib.Path(sys.argv[1])

def package_digest(root):
    digest = hashlib.sha256(b"fluke-coreml-package-v1\0")
    for path in sorted(root.rglob("*"), key=lambda item: item.relative_to(root).as_posix()):
        relative = path.relative_to(root).as_posix().encode()
        digest.update(b"D" if path.is_dir() else b"F")
        digest.update(len(relative).to_bytes(8, "big"))
        digest.update(relative)
        if path.is_file():
            digest.update(path.read_bytes())
    return digest.hexdigest()

model_digest = package_digest(release / "FlukeEmbedder.mlpackage")
catalog_digest = hashlib.sha256((release / "catalog/manifest.json").read_bytes()).hexdigest()
boundary_details = {
    "input_paths": "all fixed release inputs and exact directory layouts are safe",
    "package": "exact export schema, identity, package tree, interface, and audited tools verified",
    "catalog": "complete Task 3 published catalog contract verified",
    "digests": "package, vectors, metadata, and rights digests match exactly",
    "rights": "written model and exact-source mobile redistribution rights verified",
    "embedding_shape": "8 paired float32 embeddings have shape (N, 384)",
    "embedding_norm": "all parity embeddings are finite and L2 normalized",
    "required_reports": "all six exact-schema, digest-bound evaluation reports are present",
}
gates = [
    {"name": "model_package_digest", "passed": True, "observed": model_digest,
     "requirement": "valid lowercase SHA256 release identity", "detail": "digest is bound"},
    {"name": "catalog_manifest_digest", "passed": True, "observed": catalog_digest,
     "requirement": "valid lowercase SHA256 release identity", "detail": "digest is bound"},
]
gates.extend({"name": name, "passed": True, "observed": True,
              "requirement": "validation must pass", "detail": detail}
             for name, detail in boundary_details.items())
def count_gate(name, observed):
    return {"name": name, "passed": True, "observed": observed,
            "requirement": "positive integer sample count", "detail": "sample count is meaningful"}

def metric_gate(name, observed, comparison, threshold):
    return {"name": name, "passed": True, "observed": observed,
            "requirement": f"finite value {comparison} {threshold}", "detail": "threshold met"}

gates.extend((
    count_gate("parity_samples", 8),
    metric_gate("parity_cosine", 0.9995, ">=", 0.999),
    count_gate("closed_set_samples", 20),
    metric_gate("top_1", 0.7, ">=", 0.65),
    metric_gate("top_3", 0.85, ">=", 0.8),
    count_gate("open_set_samples", 30),
    metric_gate("false_accept", 0.04, "<=", 0.05),
))
report = {
    "catalogManifestSha256": catalog_digest,
    "gates": gates,
    "modelPackageSha256": model_digest,
    "ready": True,
    "schemaVersion": 1,
    "thresholds": {
        "false_accept": 0.05,
        "parity_cosine": 0.999,
        "top_1": 0.65,
        "top_3": 0.8,
    },
}
with open(sys.argv[2], "w", encoding="utf-8") as output:
    json.dump(report, output)
PY

expect_success "staged JSON and gates accept a temporary geometry-opacity fixture" \
  "$verifier" --build-settings-fixture "$build_settings" --shipping-resources-fixture "$shipping_resources" --project-membership-fixture "$membership_fixture" --mobile-release-directory "$release_dir" "$valid"

expect_failure "catalog proof is mandatory" \
  "mobile release directory is required" \
  "$verifier" --build-settings-fixture "$build_settings" --shipping-resources-fixture "$shipping_resources" --project-membership-fixture "$membership_fixture" "$valid"

not_ready="$test_root/not-ready"
cp -R "$release_dir" "$not_ready"
python3 - "$not_ready/mobile-release-report.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    value = json.load(source)
value["ready"] = False
with open(sys.argv[1], "w", encoding="utf-8") as output:
    json.dump(value, output)
PY
expect_failure "catalog proof must report ready true" \
  "ready must be true" \
  "$verifier" --build-settings-fixture "$build_settings" --shipping-resources-fixture "$shipping_resources" --project-membership-fixture "$membership_fixture" --mobile-release-directory "$not_ready" "$valid"

bad_digest="$test_root/bad-digest"
cp -R "$release_dir" "$bad_digest"
python3 - "$bad_digest/mobile-release-report.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    value = json.load(source)
value["catalogManifestSha256"] = "not-a-digest"
with open(sys.argv[1], "w", encoding="utf-8") as output:
    json.dump(value, output)
PY
expect_failure "catalog proof requires real lowercase SHA-256 identities" \
  "catalogManifestSha256 must be a lowercase SHA-256" \
  "$verifier" --build-settings-fixture "$build_settings" --shipping-resources-fixture "$shipping_resources" --project-membership-fixture "$membership_fixture" --mobile-release-directory "$bad_digest" "$valid"

missing_gate="$test_root/missing-gate"
cp -R "$release_dir" "$missing_gate"
python3 - "$missing_gate/mobile-release-report.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    value = json.load(source)
value["gates"] = value["gates"][:-1]
with open(sys.argv[1], "w", encoding="utf-8") as output:
    json.dump(value, output)
PY
expect_failure "catalog proof requires the exact mobile release gate set" \
  "gate-name set is incomplete or unexpected" \
  "$verifier" --build-settings-fixture "$build_settings" --shipping-resources-fixture "$shipping_resources" --project-membership-fixture "$membership_fixture" --mobile-release-directory "$missing_gate" "$valid"

wrong_threshold="$test_root/wrong-threshold"
cp -R "$release_dir" "$wrong_threshold"
python3 - "$wrong_threshold/mobile-release-report.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    value = json.load(source)
value["thresholds"]["top_1"] = 0.5
with open(sys.argv[1], "w", encoding="utf-8") as output:
    json.dump(value, output)
PY
expect_failure "catalog proof requires exact mobile release thresholds" \
  "thresholds do not match the mobile release contract" \
  "$verifier" --build-settings-fixture "$build_settings" --shipping-resources-fixture "$shipping_resources" --project-membership-fixture "$membership_fixture" --mobile-release-directory "$wrong_threshold" "$valid"

missing_observed="$test_root/missing-observed"
cp -R "$release_dir" "$missing_observed"
python3 - "$missing_observed/mobile-release-report.json" <<'PY'
import json, sys
path = sys.argv[1]
value = json.load(open(path, encoding="utf-8"))
del value["gates"][10]["observed"]
json.dump(value, open(path, "w", encoding="utf-8"))
PY
expect_failure "catalog proof requires every exact producer field" \
  "fields do not match the exact schema" \
  "$verifier" --build-settings-fixture "$build_settings" --shipping-resources-fixture "$shipping_resources" --project-membership-fixture "$membership_fixture" --mobile-release-directory "$missing_observed" "$valid"

fabricated_metric="$test_root/fabricated-metric"
cp -R "$release_dir" "$fabricated_metric"
python3 - "$fabricated_metric/mobile-release-report.json" <<'PY'
import json, sys
path = sys.argv[1]
value = json.load(open(path, encoding="utf-8"))
next(gate for gate in value["gates"] if gate["name"] == "top_1")["observed"] = 0.1
json.dump(value, open(path, "w", encoding="utf-8"))
PY
expect_failure "catalog proof rejects fabricated passing metric observations" \
  "top_1 observation does not satisfy its exact gate" \
  "$verifier" --build-settings-fixture "$build_settings" --shipping-resources-fixture "$shipping_resources" --project-membership-fixture "$membership_fixture" --mobile-release-directory "$fabricated_metric" "$valid"

fabricated_detail="$test_root/fabricated-detail"
cp -R "$release_dir" "$fabricated_detail"
python3 - "$fabricated_detail/mobile-release-report.json" <<'PY'
import json, sys
path = sys.argv[1]
value = json.load(open(path, encoding="utf-8"))
next(gate for gate in value["gates"] if gate["name"] == "rights")["detail"] = "trust me"
json.dump(value, open(path, "w", encoding="utf-8"))
PY
expect_failure "catalog proof rejects fabricated validation details" \
  "rights evidence does not match the producer contract" \
  "$verifier" --build-settings-fixture "$build_settings" --shipping-resources-fixture "$shipping_resources" --project-membership-fixture "$membership_fixture" --mobile-release-directory "$fabricated_detail" "$valid"

digest_gate_mismatch="$test_root/digest-gate-mismatch"
cp -R "$release_dir" "$digest_gate_mismatch"
python3 - "$digest_gate_mismatch/mobile-release-report.json" <<'PY'
import json, sys
path = sys.argv[1]
value = json.load(open(path, encoding="utf-8"))
next(gate for gate in value["gates"] if gate["name"] == "model_package_digest")["observed"] = "f" * 64
json.dump(value, open(path, "w", encoding="utf-8"))
PY
expect_failure "catalog proof binds digest-gate observations to report identity" \
  "model_package_digest observed digest must equal modelPackageSha256" \
  "$verifier" --build-settings-fixture "$build_settings" --shipping-resources-fixture "$shipping_resources" --project-membership-fixture "$membership_fixture" --mobile-release-directory "$digest_gate_mismatch" "$valid"

artifact_mismatch="$test_root/artifact-mismatch"
cp -R "$release_dir" "$artifact_mismatch"
printf 'tampered\n' >> "$artifact_mismatch/FlukeEmbedder.mlpackage/Data/model.bin"
expect_failure "catalog proof binds the report to actual release artifacts" \
  "modelPackageSha256 does not match the actual mobile release package" \
  "$verifier" --build-settings-fixture "$build_settings" --shipping-resources-fixture "$shipping_resources" --project-membership-fixture "$membership_fixture" --mobile-release-directory "$artifact_mismatch" "$valid"

expect_failure "test-only build settings cannot bypass production verification" \
  "restricted to FLUKE_APP_STORE_TESTING=true" \
  env -u FLUKE_APP_STORE_TESTING "$verifier" --build-settings-fixture "$build_settings" --shipping-resources-fixture "$shipping_resources" --project-membership-fixture "$membership_fixture" --mobile-release-directory "$release_dir" "$valid"

expect_failure "shipping target must be version 1.1 build 2" \
  "shipping Fluke target MARKETING_VERSION must equal 1.1" \
  "$verifier" --mobile-release-directory "$release_dir" "$valid"

missing_shipping_catalog="$test_root/missing-shipping-catalog"
cp -R "$shipping_resources" "$missing_shipping_catalog"
rm "$missing_shipping_catalog/IdentifierCatalog/metadata.json"
expect_failure "shipping app must contain the exact production catalog resources" \
  "shipping IdentifierCatalog resource is missing: metadata.json" \
  "$verifier" --build-settings-fixture "$build_settings" --shipping-resources-fixture "$missing_shipping_catalog" --project-membership-fixture "$membership_fixture" --mobile-release-directory "$release_dir" "$valid"

mismatched_shipping_catalog="$test_root/mismatched-shipping-catalog"
cp -R "$shipping_resources" "$mismatched_shipping_catalog"
printf 'tampered\n' >> "$mismatched_shipping_catalog/IdentifierCatalog/references.f16"
expect_failure "shipping catalog bytes must match the verified release" \
  "shipping IdentifierCatalog resource does not match verified release: references.f16" \
  "$verifier" --build-settings-fixture "$build_settings" --shipping-resources-fixture "$mismatched_shipping_catalog" --project-membership-fixture "$membership_fixture" --mobile-release-directory "$release_dir" "$valid"

missing_membership="$test_root/missing-membership.txt"
sed '/IdentifierCatalog\/references.f16/d' "$membership_fixture" > "$missing_membership"
expect_failure "shipping target membership must cover every identification resource" \
  "project membership fixture does not include every shipping identification resource" \
  "$verifier" --build-settings-fixture "$build_settings" --shipping-resources-fixture "$shipping_resources" --project-membership-fixture "$missing_membership" --mobile-release-directory "$release_dir" "$valid"

production_resource_release="$test_root/production-resource-release"
cp -R "$release_dir" "$production_resource_release"
rm -R "$production_resource_release/FlukeEmbedder.mlpackage"
cp -R "$repo_root/App/Fluke/Models/FlukeEmbedder.mlpackage" "$production_resource_release/FlukeEmbedder.mlpackage"
python3 - "$production_resource_release" <<'PY'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
package = root / "FlukeEmbedder.mlpackage"
digest = hashlib.sha256(b"fluke-coreml-package-v1\0")
for path in sorted(package.rglob("*"), key=lambda item: item.relative_to(package).as_posix()):
    relative = path.relative_to(package).as_posix().encode()
    digest.update(b"D" if path.is_dir() else b"F")
    digest.update(len(relative).to_bytes(8, "big"))
    digest.update(relative)
    if path.is_file():
        digest.update(path.read_bytes())
value = json.load(open(root / "mobile-release-report.json", encoding="utf-8"))
value["modelPackageSha256"] = digest.hexdigest()
next(gate for gate in value["gates"] if gate["name"] == "model_package_digest")["observed"] = digest.hexdigest()
json.dump(value, open(root / "mobile-release-report.json", "w", encoding="utf-8"))
PY
expect_failure "production app remains blocked until IdentifierCatalog is staged" \
  "shipping IdentifierCatalog resource is missing: manifest.json" \
  "$verifier" --build-settings-fixture "$build_settings" --mobile-release-directory "$production_resource_release" "$valid"

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
  "$verifier" --build-settings-fixture "$build_settings" --shipping-resources-fixture "$shipping_resources" --project-membership-fixture "$membership_fixture" --mobile-release-directory "$release_dir" "$bad_url"

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
  "$verifier" --build-settings-fixture "$build_settings" --shipping-resources-fixture "$shipping_resources" --project-membership-fixture "$membership_fixture" --mobile-release-directory "$release_dir" "$stale_processing_copy"

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
  "$verifier" --build-settings-fixture "$build_settings" --shipping-resources-fixture "$shipping_resources" --project-membership-fixture "$membership_fixture" --mobile-release-directory "$release_dir" "$stale_camera_copy"

stale_fluke_matching="$test_root/stale-fluke-matching"
cp -R "$valid" "$stale_fluke_matching"
python3 - "$stale_fluke_matching/en-US/metadata.json" <<'PY'
import json, sys
path = sys.argv[1]
value = json.load(open(path, encoding="utf-8"))
value["promotionalText"] = value["promotionalText"].replace("dorsal-fin matching for orca individuals", "fluke matching")
json.dump(value, open(path, "w", encoding="utf-8"))
PY
expect_failure "metadata rejects anatomically misleading fluke-matching copy" \
  "metadata contains stale selected-photo identification copy: fluke matching" \
  "$verifier" --build-settings-fixture "$build_settings" --shipping-resources-fixture "$shipping_resources" --project-membership-fixture "$membership_fixture" --mobile-release-directory "$release_dir" "$stale_fluke_matching"

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
  "$verifier" --build-settings-fixture "$build_settings" --shipping-resources-fixture "$shipping_resources" --project-membership-fixture "$membership_fixture" --mobile-release-directory "$release_dir" "$tracking"

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
  "$verifier" --build-settings-fixture "$build_settings" --shipping-resources-fixture "$shipping_resources" --project-membership-fixture "$membership_fixture" --mobile-release-directory "$release_dir" "$analytics"

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
  "$verifier" --build-settings-fixture "$build_settings" --shipping-resources-fixture "$shipping_resources" --project-membership-fixture "$membership_fixture" --mobile-release-directory "$release_dir" "$extra_transmission"

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
  "$verifier" --build-settings-fixture "$build_settings" --shipping-resources-fixture "$shipping_resources" --project-membership-fixture "$membership_fixture" --mobile-release-directory "$release_dir" "$missing_local_processing"

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
  "$verifier" --build-settings-fixture "$build_settings" --shipping-resources-fixture "$shipping_resources" --project-membership-fixture "$membership_fixture" --mobile-release-directory "$release_dir" "$underdeclared_privacy"

missing_account_email="$test_root/missing-account-email"
cp -R "$valid" "$missing_account_email"
python3 - "$missing_account_email/app-privacy.json" <<'PY'
import json, sys
path = sys.argv[1]
value = json.load(open(path, encoding="utf-8"))
value["transmittedOnOptionalAccountUse"].remove("account-email")
json.dump(value, open(path, "w", encoding="utf-8"))
PY
expect_failure "privacy separately discloses optional account email" \
  "$.transmittedOnOptionalAccountUse must equal" \
  "$verifier" --build-settings-fixture "$build_settings" --shipping-resources-fixture "$shipping_resources" --project-membership-fixture "$membership_fixture" --mobile-release-directory "$release_dir" "$missing_account_email"

missing_auth_flow="$test_root/missing-auth-flow"
cp -R "$valid" "$missing_auth_flow"
python3 - "$missing_auth_flow/app-privacy.json" <<'PY'
import json, sys
path = sys.argv[1]
value = json.load(open(path, encoding="utf-8"))
del value["transmittedForAppleAuthentication"]
json.dump(value, open(path, "w", encoding="utf-8"))
PY
expect_failure "privacy separately discloses Apple credential flow" \
  "$.transmittedForAppleAuthentication is required" \
  "$verifier" --build-settings-fixture "$build_settings" --shipping-resources-fixture "$shipping_resources" --project-membership-fixture "$membership_fixture" --mobile-release-directory "$release_dir" "$missing_auth_flow"

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
  "$verifier" --build-settings-fixture "$build_settings" --shipping-resources-fixture "$shipping_resources" --project-membership-fixture "$membership_fixture" --mobile-release-directory "$release_dir" "$wrong_build"

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
  "$verifier" --build-settings-fixture "$build_settings" --shipping-resources-fixture "$shipping_resources" --project-membership-fixture "$membership_fixture" --mobile-release-directory "$release_dir" "$over_limit"

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
  "$verifier" --build-settings-fixture "$build_settings" --shipping-resources-fixture "$shipping_resources" --project-membership-fixture "$membership_fixture" --mobile-release-directory "$release_dir" "$missing_schema_field"

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
  "$verifier" --build-settings-fixture "$build_settings" --shipping-resources-fixture "$shipping_resources" --project-membership-fixture "$membership_fixture" --mobile-release-directory "$release_dir" "$submitted"

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
  "$verifier" --build-settings-fixture "$build_settings" --shipping-resources-fixture "$shipping_resources" --project-membership-fixture "$membership_fixture" --mobile-release-directory "$release_dir" "$receipt_id"

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
  "$verifier" --build-settings-fixture "$build_settings" --shipping-resources-fixture "$shipping_resources" --project-membership-fixture "$membership_fixture" --mobile-release-directory "$release_dir" "$receipt_timestamp"

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
  "$verifier" --build-settings-fixture "$build_settings" --shipping-resources-fixture "$shipping_resources" --project-membership-fixture "$membership_fixture" --mobile-release-directory "$release_dir" "$wrong_export"

missing_screenshots="$test_root/missing-screenshots"
cp -R "$package_root" "$missing_screenshots"
expect_failure "screenshots fail closed while absent" \
  "requires 1-10 accepted opaque 6.9-inch screenshots" \
  "$verifier" --build-settings-fixture "$build_settings" --shipping-resources-fixture "$shipping_resources" --project-membership-fixture "$membership_fixture" --mobile-release-directory "$release_dir" "$missing_screenshots"

if ((failures > 0)); then
  printf '%d App Store 1.1 submission verifier test(s) failed\n' "$failures" >&2
  exit 1
fi

echo "App Store 1.1 submission verifier tests passed"
