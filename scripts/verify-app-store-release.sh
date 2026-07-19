#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
info_plist="${FLUKE_INFO_PLIST:-$repo_root/App/Fluke/Info.plist}"
privacy_manifest="${FLUKE_PRIVACY_MANIFEST:-$repo_root/App/Fluke/PrivacyInfo.xcprivacy}"
metadata="${FLUKE_APP_STORE_METADATA:-$repo_root/AppStore/1.0/en-US/metadata.json}"
app_icon="${FLUKE_APP_ICON_PATH:-$repo_root/App/Fluke/Assets.xcassets/AppIcon.appiconset/icon-1024.png}"
font_license="${FLUKE_FONT_LICENSE_PATH:-$repo_root/Packages/FlukeFeatures/Sources/FlukeFeatures/Resources/Fonts/OFL.txt}"

for required_file in "$info_plist" "$privacy_manifest" "$metadata" "$app_icon" "$font_license"; do
  test -f "$required_file" || {
    printf 'Missing App Store release artifact: %s\n' "$required_file" >&2
    exit 1
  }
done

python3 - "$info_plist" "$privacy_manifest" "$metadata" "$font_license" <<'PY'
import json
import plistlib
import sys

info_path, privacy_path, metadata_path, license_path = sys.argv[1:]

def load_plist(path):
    try:
        with open(path, "rb") as source:
            return plistlib.load(source)
    except (OSError, plistlib.InvalidFileException) as error:
        raise SystemExit(f"Invalid property list {path}: {error}")

info = load_plist(info_path)
if info.get("ITSAppUsesNonExemptEncryption") is not False:
    raise SystemExit("ITSAppUsesNonExemptEncryption must be false")

privacy = load_plist(privacy_path)
expected_types = [
    "NSPrivacyCollectedDataTypeEmailAddress",
    "NSPrivacyCollectedDataTypeName",
    "NSPrivacyCollectedDataTypePhotosorVideos",
    "NSPrivacyCollectedDataTypeCoarseLocation",
    "NSPrivacyCollectedDataTypeUserID",
    "NSPrivacyCollectedDataTypeOtherUserContent",
]
expected_collected_data = [
    {
        "NSPrivacyCollectedDataType": data_type,
        "NSPrivacyCollectedDataTypeLinked": True,
        "NSPrivacyCollectedDataTypePurposes": [
            "NSPrivacyCollectedDataTypePurposeAppFunctionality"
        ],
        "NSPrivacyCollectedDataTypeTracking": False,
    }
    for data_type in expected_types
]
expected_accessed_api_types = [
    {
        "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryFileTimestamp",
        "NSPrivacyAccessedAPITypeReasons": ["C617.1"],
    }
]
if privacy.get("NSPrivacyAccessedAPITypes") != expected_accessed_api_types:
    raise SystemExit(
        "PrivacyInfo.xcprivacy must declare exactly FileTimestamp C617.1"
    )
expected_privacy = {
    "NSPrivacyTracking": False,
    "NSPrivacyTrackingDomains": [],
    "NSPrivacyCollectedDataTypes": expected_collected_data,
    "NSPrivacyAccessedAPITypes": expected_accessed_api_types,
}
if privacy != expected_privacy:
    raise SystemExit(
        "PrivacyInfo.xcprivacy must declare the complete linked app-functionality "
        "data set with no tracking and only audited required-reason API access"
    )

try:
    with open(metadata_path, encoding="utf-8") as source:
        metadata = json.load(source)
except (OSError, json.JSONDecodeError) as error:
    raise SystemExit(f"Invalid App Store metadata: {error}")

required_strings = (
    "version", "name", "subtitle", "description", "keywords", "promotionalText",
    "whatsNew", "supportURL", "privacyURL", "marketingURL", "copyright", "reviewNotes",
)
for key in required_strings:
    value = metadata.get(key)
    if not isinstance(value, str) or not value.strip():
        raise SystemExit(f"metadata {key} must be a non-empty string")
    if any(marker in value.lower() for marker in ("todo", "tbd", "placeholder", "your-email")):
        raise SystemExit(f"metadata {key} contains a placeholder")

limits = {"name": 30, "subtitle": 30, "description": 4000, "promotionalText": 170}
for key, limit in limits.items():
    if len(metadata[key]) > limit:
        raise SystemExit(f"{key} exceeds {limit} characters")
if len(metadata["keywords"].encode("utf-8")) > 100:
    raise SystemExit("keywords exceeds 100 UTF-8 bytes")
if metadata["supportURL"] != "https://fluke-pnw.vercel.app/support":
    raise SystemExit("supportURL does not match the live support page")
if metadata["privacyURL"] != "https://fluke-pnw.vercel.app/privacy":
    raise SystemExit("privacyURL does not match the live privacy page")

release_copy = " ".join(
    str(metadata[key]) for key in ("description", "promotionalText", "whatsNew", "reviewNotes")
).lower()
for forbidden in ("read-only", "four tabs", "photo identification is available"):
    if forbidden in release_copy:
        raise SystemExit(f"metadata contains stale or unsupported launch copy: {forbidden}")
for required in (
    "accounts are optional", "submit", "moderation", "queued", "training",
    "rights-cleared", "sightings", "whales", "identify", "learn", "you", "atlas",
):
    if required not in release_copy:
        raise SystemExit(f"metadata is missing full-launch scope: {required}")

with open(license_path, encoding="utf-8") as source:
    license_text = source.read()
for required in (
    "The Fraunces Project Authors",
    "SIL OPEN FONT LICENSE Version 1.1",
    "PERMISSION & CONDITIONS",
    'THE FONT SOFTWARE IS PROVIDED "AS IS"',
):
    if required not in license_text:
        raise SystemExit(f"Fraunces license is incomplete: {required}")
PY

icon_width="$(sips -g pixelWidth "$app_icon" | awk '/pixelWidth/{print $2}')"
icon_height="$(sips -g pixelHeight "$app_icon" | awk '/pixelHeight/{print $2}')"
icon_has_alpha="$(sips -g hasAlpha "$app_icon" | awk '/hasAlpha/{print $2}')"
if [[ "$icon_width" != "1024" || "$icon_height" != "1024" || "$icon_has_alpha" != "no" ]]; then
  echo "App Store icon must be an opaque 1024x1024 PNG" >&2
  exit 1
fi

printf 'App Store 1.0 release artifacts are valid\n'
