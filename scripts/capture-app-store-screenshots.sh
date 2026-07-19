#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_directory="${1:-$repo_root/AppStore/1.1/en-US/screenshots/6.9-inch}"
device_name="${FLUKE_SCREENSHOT_DEVICE:-iPhone 17 Pro Max}"
runtime_identifier="${FLUKE_SCREENSHOT_RUNTIME:-com.apple.CoreSimulator.SimRuntime.iOS-26-0}"
: "${FLUKE_MODEL_CHECKOUT:?Set FLUKE_MODEL_CHECKOUT to the pinned reviewed checkout}"
: "${FLUKE_MODEL_RELEASE:?Set FLUKE_MODEL_RELEASE to its verified mobile release directory}"
if [[ -n "$(git -C "$repo_root" status --porcelain --untracked-files=all)" ]]; then
  echo "Screenshot capture requires a clean iOS checkout" >&2
  exit 1
fi
source_commit="$(git -C "$repo_root" rev-parse HEAD)"
source_tree="$(git -C "$repo_root" rev-parse 'HEAD^{tree}')"
capture_root="$(mktemp -d "${TMPDIR:-/tmp}/fluke-screenshots.XXXXXX")"
simulator_udid=""
trap 'if [[ -n "$simulator_udid" ]]; then xcrun simctl status_bar "$simulator_udid" clear >/dev/null 2>&1 || true; fi; rm -rf "$capture_root"' EXIT

if find "$output_directory" -maxdepth 1 -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' \) \
  2>/dev/null | grep -q .; then
  printf 'Screenshot destination already contains images: %s\n' "$output_directory" >&2
  exit 1
fi

simulator_environment="$capture_root/simulator.env"
GITHUB_ENV="$simulator_environment" \
  FLUKE_SIMULATOR_NAME="$device_name" \
  FLUKE_SIMULATOR_RUNTIME_IDENTIFIER="$runtime_identifier" \
  "$repo_root/scripts/prepare-ios-simulator.sh"
simulator_udid="$(awk -F= '$1 == "SIMULATOR_UDID" { print $2 }' "$simulator_environment")"
if [[ ! "$simulator_udid" =~ ^[0-9A-Fa-f-]{36}$ ]]; then
  echo "Screenshot capture received an invalid simulator UDID" >&2
  exit 1
fi
xcrun simctl status_bar "$simulator_udid" override \
  --time 9:41 --batteryState charged --batteryLevel 100 \
  --wifiBars 3 --cellularBars 4 --operatorName Fluke
xcrun simctl ui "$simulator_udid" appearance light

result_bundle="$capture_root/AppStoreScreenshots.xcresult"
attachments="$capture_root/attachments"

xcodebuild test \
  -project "$repo_root/App/Fluke.xcodeproj" \
  -scheme Fluke \
  -configuration Release \
  -destination "platform=iOS Simulator,id=$simulator_udid" \
  -only-testing:FlukeUITests/FlukeUITests/testCaptureAppStoreScreenshots \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 \
  -resultBundlePath "$result_bundle" \
  ENABLE_TESTABILITY=YES \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS=FLUKE_XCTEST_FIXTURES \
  CODE_SIGNING_ALLOWED=NO

xcrun xcresulttool export attachments \
  --path "$result_bundle" \
  --output-path "$attachments"
mkdir -p "$output_directory"
python3 - "$attachments" "$output_directory" <<'PY'
import json
import os
import shutil
import sys

attachments_root, output_root = sys.argv[1:]
with open(os.path.join(attachments_root, "manifest.json"), encoding="utf-8") as source:
    manifest = json.load(source)

expected = [
    "01-sightings", "02-whales", "03-submit", "04-identify",
    "05-atlas", "06-you", "07-learn",
]
exported = {}
for test in manifest:
    attachments = test.get("attachments", [])
    if isinstance(attachments, dict):
        attachments = [attachments]
    for attachment in attachments:
        name = attachment.get("suggestedHumanReadableName", "")
        filename = attachment.get("exportedFileName", "")
        matches = [item for item in expected if name == item or name.startswith(f"{item}_")]
        if len(matches) == 1 and filename:
            canonical_name = matches[0]
            if canonical_name in exported:
                raise SystemExit(f"Duplicate screenshot attachment for {canonical_name}")
            exported[canonical_name] = filename

if sorted(exported) != expected:
    raise SystemExit(f"Expected screenshot attachments {expected}, found {sorted(exported)}")
for name in expected:
    source = os.path.join(attachments_root, exported[name])
    shutil.copy2(source, os.path.join(output_root, f"{name}.png"))
PY

"$repo_root/scripts/verify-app-store-screenshots.sh" "$output_directory"
provenance="$output_directory/screenshot-provenance.json"
python3 "$repo_root/scripts/verify-screenshot-provenance.py" create \
  --repo "$repo_root" --screenshots "$output_directory" --manifest "$provenance" \
  --model-checkout "$FLUKE_MODEL_CHECKOUT" --release "$FLUKE_MODEL_RELEASE" \
  --source-commit "$source_commit" --source-tree "$source_tree" \
  --runtime "$runtime_identifier" --device "$device_name"
printf 'App Store screenshots exported to %s\n' "$output_directory"
