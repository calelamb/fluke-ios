#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
package_root="$repo_root/AppStore/1.1"
mobile_release_directory=""
build_settings_fixture=""
shipping_resources_fixture=""
project_membership_fixture=""

while (($# > 0)); do
  case "$1" in
    --mobile-release-directory)
      (($# >= 2)) || { echo "--mobile-release-directory requires a path" >&2; exit 2; }
      mobile_release_directory="$2"
      shift 2
      ;;
    --build-settings-fixture)
      (($# >= 2)) || { echo "--build-settings-fixture requires a path" >&2; exit 2; }
      build_settings_fixture="$2"
      shift 2
      ;;
    --shipping-resources-fixture)
      (($# >= 2)) || { echo "--shipping-resources-fixture requires a path" >&2; exit 2; }
      shipping_resources_fixture="$2"
      shift 2
      ;;
    --project-membership-fixture)
      (($# >= 2)) || { echo "--project-membership-fixture requires a path" >&2; exit 2; }
      project_membership_fixture="$2"
      shift 2
      ;;
    --*)
      printf 'unknown option: %s\n' "$1" >&2
      exit 2
      ;;
    *) break ;;
  esac
done
if (($# > 1)); then
  echo "Usage: $0 [--mobile-release-directory DIR] [test-only fixture options] [PACKAGE_ROOT]" >&2
  exit 2
fi
if (($# == 1)); then package_root="$1"; fi

required_files=(
  "$package_root/en-US/metadata.json"
  "$package_root/app-privacy.json"
  "$package_root/review-submission.json"
  "$package_root/schemas/metadata.schema.json"
  "$package_root/schemas/app-privacy.schema.json"
  "$package_root/schemas/review-submission.schema.json"
)
for required_file in "${required_files[@]}"; do
  test -f "$required_file" || {
    printf 'missing App Store 1.1 package artifact: %s\n' "$required_file" >&2
    exit 1
  }
done

python3 - "$package_root" "$repo_root/App/Fluke/PrivacyInfo.xcprivacy" <<'PY'
import json
import os
import plistlib
import sys

root = sys.argv[1]
privacy_manifest_path = sys.argv[2]

def load(relative):
    path = os.path.join(root, relative)
    try:
        with open(path, encoding="utf-8") as source:
            return json.load(source)
    except (OSError, json.JSONDecodeError) as error:
        raise SystemExit(f"invalid JSON {relative}: {error}")

def type_matches(value, expected):
    return {
        "array": isinstance(value, list),
        "boolean": isinstance(value, bool),
        "integer": isinstance(value, int) and not isinstance(value, bool),
        "null": value is None,
        "object": isinstance(value, dict),
        "string": isinstance(value, str),
    }.get(expected, False)

def validate(value, schema, path="$"):
    if "const" in schema and value != schema["const"]:
        raise SystemExit(f"{path} must equal {schema['const']}")
    if "enum" in schema and value not in schema["enum"]:
        raise SystemExit(f"{path} is not an allowed value")
    expected_type = schema.get("type")
    if expected_type is not None and not type_matches(value, expected_type):
        raise SystemExit(f"{path} must be {expected_type}")
    if isinstance(value, dict):
        properties = schema.get("properties", {})
        for key in schema.get("required", []):
            if key not in value:
                raise SystemExit(f"{path}.{key} is required")
        if schema.get("additionalProperties") is False:
            extras = sorted(set(value) - set(properties))
            if extras:
                raise SystemExit(f"{path} has unsupported fields: {', '.join(extras)}")
        for key, child in value.items():
            if key in properties:
                validate(child, properties[key], f"{path}.{key}")
    elif isinstance(value, list):
        if len(value) < schema.get("minItems", 0):
            raise SystemExit(f"{path} has too few items")
        if len(value) > schema.get("maxItems", len(value)):
            raise SystemExit(f"{path} has too many items")
        item_schema = schema.get("items")
        if item_schema is not None:
            for index, child in enumerate(value):
                validate(child, item_schema, f"{path}[{index}]")
    elif isinstance(value, str):
        if len(value) < schema.get("minLength", 0):
            raise SystemExit(f"{path} is too short")
        if len(value) > schema.get("maxLength", len(value)):
            raise SystemExit(f"{path} exceeds {schema['maxLength']} characters")

artifacts = (
    ("en-US/metadata.json", "schemas/metadata.schema.json"),
    ("app-privacy.json", "schemas/app-privacy.schema.json"),
    ("review-submission.json", "schemas/review-submission.schema.json"),
)
loaded = {}
for document_path, schema_path in artifacts:
    document = load(document_path)
    validate(document, load(schema_path))
    loaded[document_path] = document

metadata = loaded["en-US/metadata.json"]
if len(metadata["keywords"].encode("utf-8")) > 100:
    raise SystemExit("keywords exceeds 100 UTF-8 bytes")
for key, value in metadata.items():
    if isinstance(value, str) and any(marker in value.lower() for marker in ("todo", "tbd", "placeholder", "your-email")):
        raise SystemExit(f"metadata {key} contains a placeholder")
copy = " ".join((metadata["description"], metadata["promotionalText"], metadata["whatsNew"], metadata["reviewNotes"])).lower()
for required in (
    "camera frames", "photo crops", "embeddings", "match candidates", "caches", "drafts",
    "stay on device", "no analytics or tracking", "explicit sighting submission",
    "chosen location", "attached photo", "optional account", "live camera",
    "account email", "identity token", "authorization code", "dorsal fin", "orca individual",
    "without capture or upload", "ready:true",
):
    if required not in copy:
        raise SystemExit(f"metadata is missing required truthful copy: {required}")
if "https://fluke-api.onrender.com" not in metadata["reviewNotes"]:
    raise SystemExit("reviewNotes must name the exact live Fluke API URL")
for forbidden in ("choose a fluke photo", "choose a photo for matching", "fluke matching", "at a fluke"):
    if forbidden in copy:
        raise SystemExit(f"metadata contains stale selected-photo identification copy: {forbidden}")

privacy = loaded["app-privacy.json"]
actual_types = [entry["dataType"] for entry in privacy["collectedData"]]
expected_types = ["email-address", "name", "photos-or-videos", "coarse-location", "user-id", "other-user-content"]
if actual_types != expected_types:
    raise SystemExit("collectedData must match all six shipping privacy-manifest categories")
try:
    with open(privacy_manifest_path, "rb") as source:
        manifest = plistlib.load(source)
except (OSError, plistlib.InvalidFileException) as error:
    raise SystemExit(f"invalid shipping privacy manifest: {error}")
apple_to_draft = {
    "NSPrivacyCollectedDataTypeEmailAddress": "email-address",
    "NSPrivacyCollectedDataTypeName": "name",
    "NSPrivacyCollectedDataTypePhotosorVideos": "photos-or-videos",
    "NSPrivacyCollectedDataTypeCoarseLocation": "coarse-location",
    "NSPrivacyCollectedDataTypeUserID": "user-id",
    "NSPrivacyCollectedDataTypeOtherUserContent": "other-user-content",
}
manifest_entries = manifest.get("NSPrivacyCollectedDataTypes")
if not isinstance(manifest_entries, list):
    raise SystemExit("shipping privacy manifest has no collected-data declaration")
manifest_types = [apple_to_draft.get(entry.get("NSPrivacyCollectedDataType")) for entry in manifest_entries]
if manifest_types != actual_types or None in manifest_types:
    raise SystemExit("app-privacy.json must match all six shipping privacy-manifest categories")
for entry in manifest_entries:
    if entry.get("NSPrivacyCollectedDataTypeLinked") is not True or entry.get("NSPrivacyCollectedDataTypeTracking") is not False or entry.get("NSPrivacyCollectedDataTypePurposes") != ["NSPrivacyCollectedDataTypePurposeAppFunctionality"]:
        raise SystemExit("app-privacy.json must match shipping linked app-functionality declarations")

receipt = loaded["review-submission.json"]
if receipt["status"] != "draft" or receipt["submitted"] is not False:
    raise SystemExit("review submission must remain draft and unsubmitted")
if any(receipt[key] is not None for key in ("submittedAt", "acceptedAt", "lastCheckedAt")) or any(value is not None for value in receipt["appStoreConnect"].values()):
    raise SystemExit("review submission IDs and timestamps must remain null")
PY

screenshot_directory="$package_root/en-US/screenshots/6.9-inch"
shopt -s nullglob
screenshots=("$screenshot_directory"/*.png "$screenshot_directory"/*.jpg "$screenshot_directory"/*.jpeg)
if ((${#screenshots[@]} < 1 || ${#screenshots[@]} > 10)); then
  echo "App Store 1.1 requires 1-10 accepted opaque 6.9-inch screenshots; none are fabricated by this package" >&2
  exit 1
fi
for screenshot in "${screenshots[@]}"; do
  width="$(sips -g pixelWidth "$screenshot" | awk '/pixelWidth/{print $2}')"
  height="$(sips -g pixelHeight "$screenshot" | awk '/pixelHeight/{print $2}')"
  has_alpha="$(sips -g hasAlpha "$screenshot" | awk '/hasAlpha/{print $2}')"
  case "${width}x${height}" in
    1260x2736|2736x1260|1290x2796|2796x1290|1320x2868|2868x1320) ;;
    *) printf 'screenshot is not an accepted 6.9-inch size: %s\n' "$screenshot" >&2; exit 1 ;;
  esac
  [[ "$has_alpha" == "no" ]] || {
    printf 'screenshot must be opaque: %s\n' "$screenshot" >&2
    exit 1
  }
done

if [[ -n "$build_settings_fixture" ]]; then
  [[ "${FLUKE_APP_STORE_TESTING:-}" == "true" ]] || {
    echo "--build-settings-fixture is restricted to FLUKE_APP_STORE_TESTING=true" >&2
    exit 1
  }
  test -f "$build_settings_fixture" || { echo "build settings fixture does not exist" >&2; exit 1; }
  build_settings="$build_settings_fixture"
else
  build_settings="$(mktemp "${TMPDIR:-/tmp}/fluke-build-settings.XXXXXX")"
  trap 'rm -f "$build_settings"' EXIT
  xcodebuild -project "$repo_root/App/Fluke.xcodeproj" -scheme Fluke -configuration Release -showBuildSettings > "$build_settings"
fi
python3 - "$build_settings" <<'PY'
import re
import sys

values = {}
for line in open(sys.argv[1], encoding="utf-8"):
    match = re.match(r"\s*(TARGET_NAME|PRODUCT_BUNDLE_IDENTIFIER|MARKETING_VERSION|CURRENT_PROJECT_VERSION)\s*=\s*(.*?)\s*$", line)
    if match:
        values[match.group(1)] = match.group(2)
expected = {
    "TARGET_NAME": "Fluke",
    "PRODUCT_BUNDLE_IDENTIFIER": "app.fluke.Fluke",
    "MARKETING_VERSION": "1.1",
    "CURRENT_PROJECT_VERSION": "2",
}
for key, expected_value in expected.items():
    if values.get(key) != expected_value:
        raise SystemExit(f"shipping Fluke target {key} must equal {expected_value}; observed {values.get(key)!r}")
PY

[[ -n "$mobile_release_directory" ]] || {
  echo "mobile release directory is required before identification can be claimed" >&2
  exit 1
}
test -d "$mobile_release_directory" || {
  echo "mobile release directory does not exist" >&2
  exit 1
}
python3 - "$mobile_release_directory" <<'PY'
import hashlib
import json
import math
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
report_path = root / "mobile-release-report.json"
if root.is_symlink() or not root.is_dir() or report_path.is_symlink():
    raise SystemExit("mobile release directory or report is missing or unsafe")
try:
    with report_path.open(encoding="utf-8") as source:
        result = json.load(source)
except (OSError, json.JSONDecodeError) as error:
    raise SystemExit(f"invalid production catalog verifier output: {error}")
if not isinstance(result, dict):
    raise SystemExit("production catalog verifier output must be an object")
if set(result) != {"schemaVersion", "modelPackageSha256", "catalogManifestSha256", "ready", "thresholds", "gates"}:
    raise SystemExit("production catalog verifier top-level fields do not match the exact schema")
if result.get("schemaVersion") != 1:
    raise SystemExit("production catalog verifier schemaVersion must be 1")
if result.get("ready") is not True:
    raise SystemExit("production catalog verifier ready must be true")
digest_pattern = re.compile(r"^[a-f0-9]{64}$")
for key in ("modelPackageSha256", "catalogManifestSha256"):
    if not isinstance(result.get(key), str) or digest_pattern.fullmatch(result[key]) is None:
        raise SystemExit(f"production catalog verifier {key} must be a lowercase SHA-256")
expected_thresholds = {
    "false_accept": 0.05,
    "parity_cosine": 0.999,
    "top_1": 0.65,
    "top_3": 0.8,
}
if result.get("thresholds") != expected_thresholds:
    raise SystemExit("production catalog verifier thresholds do not match the mobile release contract")
expected_gate_names = {
    "model_package_digest", "catalog_manifest_digest", "input_paths", "package", "catalog",
    "digests", "rights", "embedding_shape", "embedding_norm", "required_reports",
    "parity_samples", "parity_cosine", "closed_set_samples", "top_1", "top_3",
    "open_set_samples", "false_accept",
}
gates = result.get("gates")
if not isinstance(gates, list):
    raise SystemExit("production catalog verifier gates must be an array")
expected_order = (
    "model_package_digest", "catalog_manifest_digest", "input_paths", "package", "catalog",
    "digests", "rights", "embedding_shape", "embedding_norm", "required_reports",
    "parity_samples", "parity_cosine", "closed_set_samples", "top_1", "top_3",
    "open_set_samples", "false_accept",
)
names = [gate.get("name") for gate in gates if isinstance(gate, dict)]
if tuple(names) != expected_order or set(names) != expected_gate_names:
    raise SystemExit("production catalog verifier gate-name set is incomplete or unexpected")
for gate in gates:
    if set(gate) != {"name", "passed", "observed", "requirement", "detail"}:
        raise SystemExit(f"production catalog verifier gate {gate.get('name')!r} fields do not match the exact schema")
    if gate["passed"] is not True:
        raise SystemExit("every production catalog verifier gate must pass")

gate_by_name = {gate["name"]: gate for gate in gates}
for name, digest_key in (("model_package_digest", "modelPackageSha256"), ("catalog_manifest_digest", "catalogManifestSha256")):
    gate = gate_by_name[name]
    if gate["observed"] != result[digest_key]:
        raise SystemExit(f"production catalog verifier {name} observed digest must equal {digest_key}")
    if gate["requirement"] != "valid lowercase SHA256 release identity" or gate["detail"] != "digest is bound":
        raise SystemExit(f"production catalog verifier {name} evidence text does not match the producer contract")

boundary_details = {
    "input_paths": "all fixed release inputs and exact directory layouts are safe",
    "package": "exact export schema, identity, package tree, interface, and audited tools verified",
    "catalog": "complete Task 3 published catalog contract verified",
    "digests": "package, vectors, metadata, and rights digests match exactly",
    "rights": "written model and exact-source mobile redistribution rights verified",
    "embedding_norm": "all parity embeddings are finite and L2 normalized",
    "required_reports": "all six exact-schema, digest-bound evaluation reports are present",
}
for name, detail in boundary_details.items():
    gate = gate_by_name[name]
    if gate["observed"] is not True or gate["requirement"] != "validation must pass" or gate["detail"] != detail:
        raise SystemExit(f"production catalog verifier {name} evidence does not match the producer contract")

for name in ("parity_samples", "closed_set_samples", "open_set_samples"):
    gate = gate_by_name[name]
    if isinstance(gate["observed"], bool) or not isinstance(gate["observed"], int) or gate["observed"] <= 0:
        raise SystemExit(f"production catalog verifier {name} observed must be a positive integer")
    if gate["requirement"] != "positive integer sample count" or gate["detail"] != "sample count is meaningful":
        raise SystemExit(f"production catalog verifier {name} evidence text does not match the producer contract")

shape = gate_by_name["embedding_shape"]
expected_shape_detail = f"{gate_by_name['parity_samples']['observed']} paired float32 embeddings have shape (N, 384)"
if shape["observed"] is not True or shape["requirement"] != "validation must pass" or shape["detail"] != expected_shape_detail:
    raise SystemExit("production catalog verifier embedding_shape evidence does not match parity_samples")

metric_contract = {
    "parity_cosine": (">=", 0.999), "top_1": (">=", 0.65),
    "top_3": (">=", 0.8), "false_accept": ("<=", 0.05),
}
for name, (comparison, threshold) in metric_contract.items():
    gate = gate_by_name[name]
    observed = gate["observed"]
    valid_number = isinstance(observed, (int, float)) and not isinstance(observed, bool) and math.isfinite(observed)
    threshold_met = valid_number and (observed <= threshold if comparison == "<=" else observed >= threshold)
    if not threshold_met or gate["requirement"] != f"finite value {comparison} {threshold}" or gate["detail"] != "threshold met":
        raise SystemExit(f"production catalog verifier {name} observation does not satisfy its exact gate")

def package_tree_digest(package):
    if package.is_symlink() or not package.is_dir():
        raise SystemExit("mobile release Core ML package is missing or unsafe")
    entries = sorted(package.rglob("*"), key=lambda path: path.relative_to(package).as_posix())
    if not entries:
        raise SystemExit("mobile release Core ML package must not be empty")
    digest = hashlib.sha256(b"fluke-coreml-package-v1\0")
    for path in entries:
        if path.is_symlink():
            raise SystemExit("mobile release Core ML package contains a symlink")
        relative = path.relative_to(package).as_posix().encode("utf-8")
        digest.update(b"D" if path.is_dir() else b"F")
        digest.update(len(relative).to_bytes(8, "big"))
        digest.update(relative)
        if path.is_file():
            with path.open("rb") as source:
                for chunk in iter(lambda: source.read(1024 * 1024), b""):
                    digest.update(chunk)
        elif not path.is_dir():
            raise SystemExit("mobile release Core ML package contains a non-regular entry")
    return digest.hexdigest()

model_digest = package_tree_digest(root / "FlukeEmbedder.mlpackage")
catalog_path = root / "catalog" / "manifest.json"
if catalog_path.is_symlink() or not catalog_path.is_file():
    raise SystemExit("mobile release catalog manifest is missing or unsafe")
catalog_digest = hashlib.sha256(catalog_path.read_bytes()).hexdigest()
if model_digest != result["modelPackageSha256"]:
    raise SystemExit("production report modelPackageSha256 does not match the actual mobile release package")
if catalog_digest != result["catalogManifestSha256"]:
    raise SystemExit("production report catalogManifestSha256 does not match the actual mobile release catalog manifest")
PY

if [[ -n "$shipping_resources_fixture" || -n "$project_membership_fixture" ]]; then
  [[ "${FLUKE_APP_STORE_TESTING:-}" == "true" ]] || {
    echo "shipping resource fixtures are restricted to FLUKE_APP_STORE_TESTING=true" >&2
    exit 1
  }
  [[ -n "$shipping_resources_fixture" && -n "$project_membership_fixture" ]] || {
    echo "shipping resource and project membership fixtures must be supplied together" >&2
    exit 1
  }
  shipping_resources="$shipping_resources_fixture"
  project_membership="$project_membership_fixture"
  membership_mode="fixture"
else
  shipping_resources="$repo_root/App/Fluke"
  project_membership="$repo_root/App/Fluke.xcodeproj/project.pbxproj"
  membership_mode="project"
fi

python3 - "$mobile_release_directory" "$shipping_resources" "$project_membership" "$membership_mode" <<'PY'
import hashlib
from pathlib import Path
import re
import sys

release = Path(sys.argv[1])
shipping = Path(sys.argv[2])
membership_path = Path(sys.argv[3])
mode = sys.argv[4]

def reject_symlink_path(path, boundary, label):
    relative = path.relative_to(boundary)
    current = boundary
    if boundary.is_symlink():
        raise SystemExit(f"{label} path contains a symlink")
    for component in relative.parts:
        current = current / component
        if current.is_symlink():
            raise SystemExit(f"{label} path contains a symlink")

def file_digest(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.digest()

def package_tree_digest(package):
    if package.is_symlink() or not package.is_dir():
        raise SystemExit(f"shipping model package is missing: {package}")
    entries = sorted(package.rglob("*"), key=lambda path: path.relative_to(package).as_posix())
    if not entries:
        raise SystemExit("shipping model package must not be empty")
    digest = hashlib.sha256(b"fluke-coreml-package-v1\0")
    for path in entries:
        if path.is_symlink():
            raise SystemExit("shipping model package contains a symlink")
        relative = path.relative_to(package).as_posix().encode("utf-8")
        digest.update(b"D" if path.is_dir() else b"F")
        digest.update(len(relative).to_bytes(8, "big"))
        digest.update(relative)
        if path.is_file():
            with path.open("rb") as source:
                for chunk in iter(lambda: source.read(1024 * 1024), b""):
                    digest.update(chunk)
        elif not path.is_dir():
            raise SystemExit("shipping model package contains a non-regular entry")
    return digest.hexdigest()

release_model = release / "FlukeEmbedder.mlpackage"
shipping_model = shipping / "Models/FlukeEmbedder.mlpackage"
reject_symlink_path(release_model, release, "verified model")
reject_symlink_path(shipping_model, shipping, "shipping model")
if package_tree_digest(release_model) != package_tree_digest(shipping_model):
    raise SystemExit("shipping model package does not match the verified mobile release package")

catalog_files = ("manifest.json", "metadata.json", "references.f16")
for filename in catalog_files:
    source = release / "catalog" / filename
    destination = shipping / "IdentifierCatalog" / filename
    reject_symlink_path(source, release, "verified catalog")
    reject_symlink_path(destination, shipping, "shipping catalog")
    if source.is_symlink() or not source.is_file():
        raise SystemExit(f"verified mobile release catalog file is missing: {filename}")
    if destination.is_symlink() or not destination.is_file():
        raise SystemExit(f"shipping IdentifierCatalog resource is missing: {filename}")
    if file_digest(source) != file_digest(destination):
        raise SystemExit(f"shipping IdentifierCatalog resource does not match verified release: {filename}")

try:
    membership = membership_path.read_text(encoding="utf-8")
except OSError as error:
    raise SystemExit(f"cannot inspect shipping project resource membership: {error}")
resource_paths = (
    "Models/FlukeEmbedder.mlpackage",
    "IdentifierCatalog/manifest.json",
    "IdentifierCatalog/metadata.json",
    "IdentifierCatalog/references.f16",
)
if mode == "fixture":
    required_lines = {"TARGET_NAME=Fluke", "SYNCHRONIZED_RESOURCE_ROOT=App/Fluke", *(f"RESOURCE={path}" for path in resource_paths)}
    if len(membership.splitlines()) != len(required_lines) or set(membership.splitlines()) != required_lines:
        raise SystemExit("project membership fixture does not include every shipping identification resource")
else:
    root_match = re.search(
        r"(?ms)^\s*([A-F0-9]+) /\* Fluke \*/ = \{\s*isa = PBXFileSystemSynchronizedRootGroup;.*?\s+path = Fluke;.*?^\s*\};",
        membership,
    )
    target_match = re.search(
        r"(?ms)^\s*[A-F0-9]+ /\* Fluke \*/ = \{\s*isa = PBXNativeTarget;(.*?)^\s*\};",
        membership,
    )
    resource_phase = None if target_match is None else re.search(r"([A-F0-9]+) /\* Resources \*/", target_match.group(1))
    synchronized_contract = bool(
        root_match
        and target_match
        and root_match.group(1) in target_match.group(1)
        and "fileSystemSynchronizedGroups" in target_match.group(1)
        and resource_phase
        and re.search(
            rf"(?ms)^\s*{resource_phase.group(1)} /\* Resources \*/ = \{{\s*isa = PBXResourcesBuildPhase;",
            membership,
        )
    )
    excluded = any(path in membership.split("membershipExceptions = (", 1)[-1].split(");", 1)[0] for path in resource_paths)
    if not synchronized_contract or excluded:
        raise SystemExit("Fluke target does not prove synchronized project membership for identification resources")
PY

printf 'App Store 1.1 submission package is valid for version 1.1 build 2\n'
