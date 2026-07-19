#!/usr/bin/env bash

set -euo pipefail

if (($# != 1)); then
  printf 'Usage: %s <archive.xcarchive>\n' "$0" >&2
  exit 2
fi

python3 - "$1" <<'PY'
import os
import plistlib
import sys

archive = os.path.realpath(sys.argv[1])
archive_info_path = os.path.join(archive, "Info.plist")
try:
    with open(archive_info_path, "rb") as source:
        archive_info = plistlib.load(source)
except (OSError, plistlib.InvalidFileException) as error:
    raise SystemExit(f"invalid archive Info.plist: {error}")

application_path = archive_info.get("ApplicationProperties", {}).get("ApplicationPath")
if not isinstance(application_path, str) or not application_path.endswith(".app"):
    raise SystemExit("archive application path is missing or invalid")
products_root = os.path.realpath(os.path.join(archive, "Products"))
app_path = os.path.realpath(os.path.join(products_root, application_path))
if os.path.commonpath([products_root, app_path]) != products_root:
    raise SystemExit("archive application path escapes Products")

try:
    with open(os.path.join(app_path, "Info.plist"), "rb") as source:
        app_info = plistlib.load(source)
except (OSError, plistlib.InvalidFileException) as error:
    raise SystemExit(f"invalid archived app Info.plist: {error}")
if app_info.get("ITSAppUsesNonExemptEncryption") is not False:
    raise SystemExit("archived app ITSAppUsesNonExemptEncryption must be false")

privacy_path = os.path.join(app_path, "PrivacyInfo.xcprivacy")
if not os.path.isfile(privacy_path):
    raise SystemExit("archived app is missing PrivacyInfo.xcprivacy")
try:
    with open(privacy_path, "rb") as source:
        privacy = plistlib.load(source)
except (OSError, plistlib.InvalidFileException) as error:
    raise SystemExit(f"invalid archived privacy manifest: {error}")
expected_types = [
    "NSPrivacyCollectedDataTypeEmailAddress",
    "NSPrivacyCollectedDataTypeName",
    "NSPrivacyCollectedDataTypePhotosorVideos",
    "NSPrivacyCollectedDataTypeCoarseLocation",
    "NSPrivacyCollectedDataTypeUserID",
    "NSPrivacyCollectedDataTypeOtherUserContent",
]
expected_accessed_api_types = [
    {
        "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryFileTimestamp",
        "NSPrivacyAccessedAPITypeReasons": ["C617.1"],
    }
]
if privacy.get("NSPrivacyAccessedAPITypes") != expected_accessed_api_types:
    raise SystemExit(
        "archived privacy manifest must declare exactly FileTimestamp C617.1"
    )
expected_privacy = {
    "NSPrivacyTracking": False,
    "NSPrivacyTrackingDomains": [],
    "NSPrivacyCollectedDataTypes": [
        {
            "NSPrivacyCollectedDataType": data_type,
            "NSPrivacyCollectedDataTypeLinked": True,
            "NSPrivacyCollectedDataTypePurposes": [
                "NSPrivacyCollectedDataTypePurposeAppFunctionality"
            ],
            "NSPrivacyCollectedDataTypeTracking": False,
        }
        for data_type in expected_types
    ],
    "NSPrivacyAccessedAPITypes": expected_accessed_api_types,
}
if privacy != expected_privacy:
    raise SystemExit("archived privacy manifest does not match the full launch data use")

license_paths = []
for directory, _, filenames in os.walk(app_path):
    if "OFL.txt" in filenames:
        license_paths.append(os.path.join(directory, "OFL.txt"))
if not license_paths:
    raise SystemExit("archived app is missing the Fraunces OFL.txt notice")

required_license_text = (
    "The Fraunces Project Authors",
    "SIL OPEN FONT LICENSE Version 1.1",
    "PERMISSION & CONDITIONS",
    'THE FONT SOFTWARE IS PROVIDED "AS IS"',
)
for path in license_paths:
    try:
        with open(path, encoding="utf-8") as source:
            text = source.read()
    except (OSError, UnicodeError):
        continue
    if all(required in text for required in required_license_text):
        print(f"Archived App Store privacy and Fraunces notice are valid in {app_path}")
        break
else:
    raise SystemExit("archived Fraunces OFL.txt notice is incomplete")
PY
