#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "Usage: $0 (--dry-run|--upload) --source-sha SHA --model-checkout DIR --release DIR --device-report FILE" >&2
  exit 2
}

mode=""
source_sha=""
model_checkout=""
release_directory=""
device_report=""
while (($#)); do
  case "$1" in
    --dry-run|--upload) [[ -z "$mode" ]] || usage; mode="$1"; shift ;;
    --source-sha) source_sha="${2:-}"; shift 2 ;;
    --model-checkout) model_checkout="${2:-}"; shift 2 ;;
    --release) release_directory="${2:-}"; shift 2 ;;
    --device-report) device_report="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done
[[ -n "$mode" && "$source_sha" =~ ^[0-9a-f]{40}$ && -n "$model_checkout" && -n "$release_directory" && -n "$device_report" ]] || usage

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
head_sha="$(git -C "$repo_root" rev-parse HEAD)"
head_tree="$(git -C "$repo_root" rev-parse 'HEAD^{tree}')"
[[ "$head_sha" == "$source_sha" ]] || { echo "Requested source SHA is not checked out" >&2; exit 1; }
[[ -z "$(git -C "$repo_root" status --porcelain --untracked-files=all)" ]] || { echo "App Store archive requires a clean checkout" >&2; exit 1; }

screenshots="$repo_root/AppStore/1.1/en-US/screenshots/6.9-inch"
provenance="$screenshots/screenshot-provenance.json"
runtime="${FLUKE_SCREENSHOT_RUNTIME:-com.apple.CoreSimulator.SimRuntime.iOS-26-0}"
device="${FLUKE_SCREENSHOT_DEVICE:-iPhone 17 Pro Max}"
python3 "$repo_root/scripts/verify-screenshot-provenance.py" verify \
  --repo "$repo_root" --screenshots "$screenshots" --manifest "$provenance" \
  --model-checkout "$model_checkout" --release "$release_directory" \
  --source-commit "$source_sha" --source-tree "$head_tree" --runtime "$runtime" --device "$device"
python3 "$repo_root/scripts/verify-device-accessibility-report.py" "$device_report"

output_root="$repo_root/build/app-store-1.1"
archive="$output_root/Fluke-1.1-2.xcarchive"
export_directory="$output_root/export"
log="$output_root/release.log"
digests="$output_root/digests.json"
mkdir -p "$output_root"
[[ ! -e "$archive" && ! -e "$export_directory" ]] || { echo "Refusing to overwrite an existing archive/export" >&2; exit 1; }
{
  printf 'mode=%s\nsource_sha=%s\nsource_tree=%s\n' "$mode" "$source_sha" "$head_tree"
  printf 'version=1.1\nbuild=2\n'
} >"$log"

FLUKE_MODEL_CHECKOUT="$model_checkout" FLUKE_MODEL_RELEASE="$release_directory" \
  xcodebuild archive -project "$repo_root/App/Fluke.xcodeproj" -scheme Fluke \
  -configuration Release -destination 'generic/platform=iOS' -archivePath "$archive" \
  MARKETING_VERSION=1.1 CURRENT_PROJECT_VERSION=2 | tee -a "$log"
"$repo_root/scripts/verify-app-store-release.sh"
"$repo_root/scripts/verify-app-store-archive.sh" "$archive"
"$repo_root/scripts/verify-archive-metadata.sh" "$archive"
"$repo_root/scripts/verify-app-store-1-1-submission.sh" \
  "$model_checkout" "$release_directory" "$archive"
xcodebuild -exportArchive -archivePath "$archive" -exportPath "$export_directory" \
  -exportOptionsPlist "$repo_root/App/ExportOptions.plist" | tee -a "$log"

python3 - "$archive" "$export_directory" "$digests" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

archive, export, output = map(Path, sys.argv[1:])
files = tuple(sorted(path for root in (archive, export) for path in root.rglob("*") if path.is_file()))
payload = {
    "schemaVersion": 1,
    "artifacts": {
        str(path.relative_to(path.parents[2])): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in files
    },
}
output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY

if [[ "$mode" == "--dry-run" ]]; then
  echo "Archive/export dry run complete; no upload attempted"
  exit 0
fi
: "${ASC_KEY_ID:?ASC_KEY_ID is required for --upload}"
: "${ASC_ISSUER_ID:?ASC_ISSUER_ID is required for --upload}"
ipa_files=("$export_directory"/*.ipa)
[[ ${#ipa_files[@]} -eq 1 && -f "${ipa_files[0]}" ]] || { echo "Upload requires exactly one exported IPA" >&2; exit 1; }
xcrun altool --upload-app --type ios --file "${ipa_files[0]}" \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
echo "App Store Connect upload accepted"
