#!/usr/bin/env bash

set -euo pipefail

if (($# != 3)); then
  printf 'Usage: %s <archive.xcarchive> <bundle-id> <minimum-os>\n' "$0" >&2
  exit 2
fi

readonly expected_team_id="86RBV2JZ8F"

binary_path="$(python3 - "$1" "$2" "$3" "$expected_team_id" <<'PY'
import os
import plistlib
import sys

archive, expected_bundle_id, expected_minimum_os, expected_team_id = sys.argv[1:]
archive_info_path = os.path.join(archive, "Info.plist")
try:
    with open(archive_info_path, "rb") as source:
        archive_info = plistlib.load(source)
except (OSError, plistlib.InvalidFileException) as error:
    raise SystemExit(f"invalid archive Info.plist: {error}")

properties = archive_info.get("ApplicationProperties", {})
if properties.get("CFBundleIdentifier") != expected_bundle_id:
    raise SystemExit("archive bundle identifier mismatch")
signing_identity = properties.get("SigningIdentity")
if signing_identity is not None and not isinstance(signing_identity, str):
    raise SystemExit("archive signing identity is invalid")
# An unsigned verification archive records either no SigningIdentity or an
# empty one depending on the Xcode host; both mean "unsigned" here.
signing_identity = (signing_identity or "").strip()
distribution_prefixes = ("Apple Distribution:", "iPhone Distribution:")
if signing_identity and not signing_identity.startswith(distribution_prefixes):
    raise SystemExit("signed archive must use an Apple or iPhone Distribution identity")
if signing_identity and not signing_identity.endswith(f" ({expected_team_id})"):
    raise SystemExit("signed archive distribution identity team mismatch")

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

if [[ "$(python3 - "$1" <<'PY'
import plistlib
import sys
with open(f"{sys.argv[1]}/Info.plist", "rb") as source:
    print("signed" if plistlib.load(source).get("ApplicationProperties", {}).get("SigningIdentity") else "unsigned")
PY
)" == "signed" ]]; then
  app_path="$(dirname "$binary_path")"
  codesign --verify --deep --strict "$app_path" >/dev/null 2>&1 || {
    printf 'signed archive app bundle failed deep strict code-signature verification\n' >&2
    exit 1
  }

  profile_path="$app_path/embedded.mobileprovision"
  if [[ ! -f "$profile_path" ]]; then
    printf 'signed archive is missing embedded.mobileprovision\n' >&2
    exit 1
  fi

  signing_check_root="$(mktemp -d "${TMPDIR:-/tmp}/fluke-signing-check.XXXXXX")"
  trap 'rm -rf "$signing_check_root"' EXIT
  signed_entitlements_path="$signing_check_root/signed-entitlements.plist"
  decoded_profile_path="$signing_check_root/embedded-profile.plist"
  codesign -d --entitlements :- "$app_path" \
    >"$signed_entitlements_path" 2>/dev/null || {
      printf 'unable to read signed archive entitlements\n' >&2
      exit 1
    }
  security cms -D -i "$profile_path" >"$decoded_profile_path" 2>/dev/null || {
    printf 'unable to decode signed archive provisioning profile\n' >&2
    exit 1
  }

  python3 - "$signed_entitlements_path" "$decoded_profile_path" "$2" \
    "$expected_team_id" <<'PY'
import plistlib
import sys

entitlements_path, profile_path, bundle_id, expected_team_id = sys.argv[1:]


def load_plist(path, label):
    try:
        with open(path, "rb") as source:
            value = plistlib.load(source)
    except (OSError, plistlib.InvalidFileException) as error:
        raise SystemExit(f"invalid {label}: {error}")
    if not isinstance(value, dict):
        raise SystemExit(f"invalid {label}: expected a dictionary")
    return value


signed = load_plist(entitlements_path, "signed archive entitlements")
profile = load_plist(profile_path, "embedded provisioning profile")
profile_entitlements = profile.get("Entitlements")
if not isinstance(profile_entitlements, dict):
    raise SystemExit("embedded provisioning profile entitlements are missing")

expected_app_identifier = f"{expected_team_id}.{bundle_id}"
if signed.get("com.apple.developer.team-identifier") != expected_team_id:
    raise SystemExit("signed archive team identifier mismatch")
if signed.get("application-identifier") != expected_app_identifier:
    raise SystemExit("signed archive application identifier mismatch")
if signed.get("com.apple.developer.applesignin") != ["Default"]:
    raise SystemExit("signed archive Sign in with Apple entitlement mismatch")

if profile.get("TeamIdentifier") != [expected_team_id]:
    raise SystemExit("embedded provisioning profile team identifier mismatch")
if profile.get("ApplicationIdentifierPrefix") != [expected_team_id]:
    raise SystemExit("embedded provisioning profile application prefix mismatch")
if profile_entitlements.get("application-identifier") != expected_app_identifier:
    raise SystemExit("embedded provisioning profile application identifier mismatch")
if profile_entitlements.get("com.apple.developer.applesignin") != ["Default"]:
    raise SystemExit("embedded provisioning profile Sign in with Apple entitlement mismatch")
PY
else
  if codesign --verify "$binary_path" >/dev/null 2>&1; then
    printf 'unsigned archive metadata contains a signed executable\n' >&2
    exit 1
  fi
fi

printf 'Archive metadata and signature state are valid for %s\n' "$2"
