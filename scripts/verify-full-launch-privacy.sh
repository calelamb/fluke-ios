#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "${1:-}" == "--root" ]]; then
  [[ $# -eq 2 ]] || { echo "usage: $0 [--root REPOSITORY_ROOT]" >&2; exit 2; }
  repo_root="$2"
elif [[ $# -ne 0 ]]; then
  echo "usage: $0 [--root REPOSITORY_ROOT]" >&2
  exit 2
fi

python3 - "$repo_root" <<'PY'
import plistlib
import sys
from pathlib import Path

root = Path(sys.argv[1])

def load(relative):
    path = root / relative
    if not path.is_file():
        raise SystemExit(f"missing privacy contract file: {relative}")
    with path.open("rb") as source:
        return plistlib.load(source)

info = load("App/Fluke/Info.plist")
entitlements = load("App/Fluke/Fluke.entitlements")
privacy = load("App/Fluke/PrivacyInfo.xcprivacy")

camera = info.get("NSCameraUsageDescription")
expected_camera = (
    "Fluke uses the camera only when you choose to attach an orca photo to a sighting "
    "or, when identification is available, compare dorsal-fin visual similarity."
)
if camera != expected_camera:
    raise SystemExit("camera usage description must be specific to explicit photo actions")

if any(key.startswith("NSLocation") and key.endswith("UsageDescription") for key in info):
    raise SystemExit("location permission descriptions must be absent")
if any(key.startswith("NSPhotoLibrary") and key.endswith("UsageDescription") for key in info):
    raise SystemExit("broad photo-library usage descriptions must be absent; PhotosPicker is selection-only")
if "NSUserTrackingUsageDescription" in info:
    raise SystemExit("ATT usage description must be absent")

ats = info.get("NSAppTransportSecurity", {})
if not isinstance(ats, dict) or any(
    ats.get(key) is True
    for key in ("NSAllowsArbitraryLoads", "NSAllowsArbitraryLoadsForMedia", "NSAllowsArbitraryLoadsInWebContent")
):
    raise SystemExit("ATS must remain enabled")

if entitlements.get("com.apple.developer.applesignin") != ["Default"]:
    raise SystemExit("Sign in with Apple entitlement must contain only Default")

if privacy.get("NSPrivacyTracking") is not False:
    raise SystemExit("tracking must be false")
if privacy.get("NSPrivacyTrackingDomains") != []:
    raise SystemExit("tracking domains must be empty")

expected_types = {
    "NSPrivacyCollectedDataTypeEmailAddress",
    "NSPrivacyCollectedDataTypeName",
    "NSPrivacyCollectedDataTypePhotosorVideos",
    "NSPrivacyCollectedDataTypeCoarseLocation",
    "NSPrivacyCollectedDataTypeUserID",
    "NSPrivacyCollectedDataTypeOtherUserContent",
}
entries = privacy.get("NSPrivacyCollectedDataTypes")
if not isinstance(entries, list) or {entry.get("NSPrivacyCollectedDataType") for entry in entries} != expected_types:
    raise SystemExit("privacy manifest must declare exact linked-data categories")
for entry in entries:
    if entry.get("NSPrivacyCollectedDataTypeLinked") is not True:
        raise SystemExit("all collected data categories must be linked to the user")
    if entry.get("NSPrivacyCollectedDataTypeTracking") is not False:
        raise SystemExit("collected data categories must not be used for tracking")
    if entry.get("NSPrivacyCollectedDataTypePurposes") != ["NSPrivacyCollectedDataTypePurposeAppFunctionality"]:
        raise SystemExit("collected data must be used only for app functionality")

# CatalogArtifactReader uses fstat only to bound app-owned resource reads. Apple maps
# that use to File Timestamp C617.1:
# https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
expected_accessed_api_types = [
    {
        "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryFileTimestamp",
        "NSPrivacyAccessedAPITypeReasons": ["C617.1"],
    }
]
if privacy.get("NSPrivacyAccessedAPITypes") != expected_accessed_api_types:
    raise SystemExit(
        "required-reason API declarations must contain exactly FileTimestamp C617.1"
    )

print("full-launch privacy contract verified")
PY
