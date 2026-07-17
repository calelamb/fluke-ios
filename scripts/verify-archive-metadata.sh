#!/usr/bin/env bash

set -euo pipefail

if (($# != 3)); then
  printf 'Usage: %s <archive.xcarchive> <bundle-id> <minimum-os>\n' "$0" >&2
  exit 2
fi

binary_path="$(python3 - "$1" "$2" "$3" <<'PY'
import os
import plistlib
import sys

archive, expected_bundle_id, expected_minimum_os = sys.argv[1:]
archive_info_path = os.path.join(archive, "Info.plist")
try:
    with open(archive_info_path, "rb") as source:
        archive_info = plistlib.load(source)
except (OSError, plistlib.InvalidFileException) as error:
    raise SystemExit(f"invalid archive Info.plist: {error}")

properties = archive_info.get("ApplicationProperties", {})
if properties.get("CFBundleIdentifier") != expected_bundle_id:
    raise SystemExit("archive bundle identifier mismatch")
if properties.get("SigningIdentity"):
    raise SystemExit("archive metadata unexpectedly contains a signing identity")

application_path = properties.get("ApplicationPath")
if not isinstance(application_path, str) or not application_path.endswith(".app"):
    raise SystemExit("archive application path is missing or invalid")
products_root = os.path.realpath(os.path.join(archive, "Products"))
app_path = os.path.realpath(os.path.join(products_root, application_path))
if os.path.commonpath([products_root, app_path]) != products_root:
    raise SystemExit("archive application path escapes Products")

app_info_path = os.path.join(app_path, "Info.plist")
try:
    with open(app_info_path, "rb") as source:
        app_info = plistlib.load(source)
except (OSError, plistlib.InvalidFileException) as error:
    raise SystemExit(f"invalid archived app Info.plist: {error}")

checks = {
    "CFBundleIdentifier": expected_bundle_id,
    "DTPlatformName": "iphoneos",
    "MinimumOSVersion": expected_minimum_os,
}
for key, expected in checks.items():
    if app_info.get(key) != expected:
        raise SystemExit(f"archived app {key} mismatch")
if app_info.get("UIDeviceFamily") != [1]:
    raise SystemExit("archived app must target iPhone only")

for version_key in ("CFBundleShortVersionString", "CFBundleVersion"):
    value = app_info.get(version_key)
    if not isinstance(value, str) or not value.strip():
        raise SystemExit(f"archived app {version_key} is missing")
    if properties.get(version_key) != value:
        raise SystemExit(f"archive {version_key} does not match archived app")

executable = app_info.get("CFBundleExecutable")
binary_path = os.path.join(app_path, executable) if isinstance(executable, str) else ""
if not binary_path or not os.path.isfile(binary_path) or not os.access(binary_path, os.X_OK):
    raise SystemExit("archived app executable is missing")
print(binary_path)
PY
)"

if codesign --verify "$binary_path" >/dev/null 2>&1; then
  printf 'archive executable is unexpectedly signed\n' >&2
  exit 1
fi

printf 'Unsigned archive metadata is valid for %s\n' "$2"
