#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
package_root="$repo_root/AppStore/1.1"
catalog_verification=""

if [[ "${1:-}" == "--catalog-verification" ]]; then
  (($# >= 2)) || { echo "--catalog-verification requires a path" >&2; exit 2; }
  catalog_verification="$2"
  shift 2
fi
if (($# > 1)); then
  echo "Usage: $0 [--catalog-verification FILE] [PACKAGE_ROOT]" >&2
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
    "chosen location", "attached photo", "optional account", "name and user id", "live camera",
    "without capture or upload", "ready:true",
):
    if required not in copy:
        raise SystemExit(f"metadata is missing required truthful copy: {required}")
if "https://fluke-api.onrender.com" not in metadata["reviewNotes"]:
    raise SystemExit("reviewNotes must name the exact live Fluke API URL")
for forbidden in ("choose a fluke photo", "choose a photo for matching"):
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

[[ -n "$catalog_verification" ]] || {
  echo "production catalog verifier output is required before identification can be claimed" >&2
  exit 1
}
test -f "$catalog_verification" || {
  echo "production catalog verifier output does not exist" >&2
  exit 1
}
python3 - "$catalog_verification" <<'PY'
import json
import re
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as source:
        result = json.load(source)
except (OSError, json.JSONDecodeError) as error:
    raise SystemExit(f"invalid production catalog verifier output: {error}")
if not isinstance(result, dict):
    raise SystemExit("production catalog verifier output must be an object")
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
names = [gate.get("name") for gate in gates if isinstance(gate, dict)]
if len(names) != len(expected_gate_names) or set(names) != expected_gate_names:
    raise SystemExit("production catalog verifier gate-name set is incomplete or unexpected")
if any(gate.get("passed") is not True for gate in gates):
    raise SystemExit("every production catalog verifier gate must pass")
PY

printf 'App Store 1.1 submission package is valid for version 1.1 build 2\n'
