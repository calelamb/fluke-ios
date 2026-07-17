#!/usr/bin/env bash

set -u

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture_verifier="$repo_root/scripts/verify-contract-fixtures.sh"
coverage_verifier="$repo_root/scripts/verify-coverage.sh"
swift_coverage_verifier="$repo_root/scripts/verify-swift-package-coverage.sh"
archive_verifier="$repo_root/scripts/verify-archive-metadata.sh"
app_store_archive_verifier="$repo_root/scripts/verify-app-store-archive.sh"
boundary_verifier="$repo_root/scripts/verify-release-a-boundaries.sh"
app_store_verifier="$repo_root/scripts/verify-app-store-release.sh"
screenshot_verifier="$repo_root/scripts/verify-app-store-screenshots.sh"
screenshot_capture="$repo_root/scripts/capture-app-store-screenshots.sh"
simulator_preparer="$repo_root/scripts/prepare-ios-simulator.sh"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/fluke-verifier-tests.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT

failures=0

expect_success() {
  local name="$1"
  shift
  if ! output="$("$@" 2>&1)"; then
    printf 'FAIL: %s\n%s\n' "$name" "$output" >&2
    failures=$((failures + 1))
  fi
}

expect_failure() {
  local name="$1"
  local message="$2"
  shift 2
  if output="$("$@" 2>&1)"; then
    printf 'FAIL: %s unexpectedly succeeded\n' "$name" >&2
    failures=$((failures + 1))
  elif [[ "$output" != *"$message"* ]]; then
    printf 'FAIL: %s did not report %q\n%s\n' "$name" "$message" "$output" >&2
    failures=$((failures + 1))
  fi
}

make_fixture_set() {
  local directory="$1"
  mkdir -p "$directory"
  printf '{"accounts":false}\n' >"$directory/capabilities.json"
  printf '[]\n' >"$directory/whales.json"
}

client_fixtures="$test_root/client"
api_root="$test_root/api"
make_fixture_set "$client_fixtures"
make_fixture_set "$api_root/contracts/fixtures"
(
  cd "$client_fixtures"
  shasum -a 256 capabilities.json whales.json
) >"$test_root/fixtures.sha256"

expect_success "canonical fixture set passes" \
  "$fixture_verifier" --client "$client_fixtures" --manifest "$test_root/fixtures.sha256" \
  --no-upstream
expect_success "matching upstream fixture set passes" \
  "$fixture_verifier" --client "$client_fixtures" --manifest "$test_root/fixtures.sha256" \
  --api-root "$api_root"

printf '{"accounts":true}\n' >"$client_fixtures/capabilities.json"
expect_failure "changed fixture bytes fail" "checksum mismatch" \
  "$fixture_verifier" --client "$client_fixtures" --manifest "$test_root/fixtures.sha256" \
  --no-upstream
printf '{"accounts":false}\n' >"$client_fixtures/capabilities.json"
printf '{}\n' >"$client_fixtures/extra.json"
expect_failure "extra packaged fixture fails" "unexpected packaged fixture" \
  "$fixture_verifier" --client "$client_fixtures" --manifest "$test_root/fixtures.sha256" \
  --no-upstream
rm "$client_fixtures/extra.json"
printf '{}\n' >"$api_root/contracts/fixtures/extra.json"
expect_failure "upstream fixture set drift fails" "upstream fixture set differs" \
  "$fixture_verifier" --client "$client_fixtures" --manifest "$test_root/fixtures.sha256" \
  --api-root "$api_root"

cat >"$test_root/coverage.json" <<'JSON'
{"targets":[
  {"name":"Fluke.app","lineCoverage":0.80,"coveredLines":80,"executableLines":100},
  {"name":"FlukeTests.xctest","lineCoverage":1.0,"coveredLines":50,"executableLines":50}
]}
JSON
expect_success "coverage accepts exact threshold" \
  "$coverage_verifier" "$test_root/coverage.json" Fluke.app 80
expect_failure "coverage rejects insufficient lines" "below required 80.01%" \
  "$coverage_verifier" "$test_root/coverage.json" Fluke.app 80.01
expect_failure "coverage rejects a missing target" "coverage target not found" \
  "$coverage_verifier" "$test_root/coverage.json" Missing.app 80
python3 - "$test_root/coverage.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as source:
    report = json.load(source)
report["targets"][0].update(lineCoverage=0.9, coveredLines=10)
with open(path, "w", encoding="utf-8") as output:
    json.dump(report, output)
PY
expect_failure "coverage rejects inconsistent counts" "coverage report is inconsistent" \
  "$coverage_verifier" "$test_root/coverage.json" Fluke.app 80

simulator_bin="$test_root/simulator-bin"
mkdir -p "$simulator_bin"
cat >"$simulator_bin/xcrun" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == "simctl list devices available --json" ]]; then
  cat "$FLUKE_SIMULATOR_LIST_JSON"
  exit 0
fi
printf '%s\n' "$*" >>"$FLUKE_SIMULATOR_COMMAND_CAPTURE"
if [[ "$1 $2" == "simctl bootstatus" && "${FLUKE_SIMULATOR_BOOTSTATUS_MODE:-}" == "recover-once" ]]; then
  count="$(cat "${FLUKE_SIMULATOR_BOOTSTATUS_COUNT}" 2>/dev/null || printf 0)"
  printf '%s' "$((count + 1))" >"$FLUKE_SIMULATOR_BOOTSTATUS_COUNT"
  if [[ "$count" == "0" ]]; then
    sleep 1
  fi
fi
if [[ "$1 $2" == "simctl bootstatus" && "${FLUKE_SIMULATOR_BOOTSTATUS_MODE:-}" == "always-timeout" ]]; then
  sleep 1
fi
SH
chmod +x "$simulator_bin/xcrun"
cat >"$test_root/simulators.json" <<'JSON'
{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-0":[
  {"name":"iPhone 17","udid":"11111111-2222-3333-4444-555555555555","state":"Shutdown","isAvailable":true}
]}}
JSON
simulator_env="$test_root/simulator.env"
expect_success "simulator preparer resolves and boots one UDID" env \
  PATH="$simulator_bin:$PATH" \
  GITHUB_ENV="$simulator_env" \
  FLUKE_SIMULATOR_LIST_JSON="$test_root/simulators.json" \
  FLUKE_SIMULATOR_COMMAND_CAPTURE="$test_root/simulator-commands" \
  "$simulator_preparer"
grep -Fxq 'SIMULATOR_UDID=11111111-2222-3333-4444-555555555555' "$simulator_env" || failures=$((failures + 1))
grep -Fxq 'SIMULATOR_DESTINATION=platform=iOS Simulator,id=11111111-2222-3333-4444-555555555555' "$simulator_env" || failures=$((failures + 1))
grep -Fxq 'FLUKE_TEST_DESTINATION=platform=iOS Simulator,id=11111111-2222-3333-4444-555555555555' "$simulator_env" || failures=$((failures + 1))
grep -Fxq 'simctl boot 11111111-2222-3333-4444-555555555555' "$test_root/simulator-commands" || failures=$((failures + 1))
grep -Fxq 'simctl bootstatus 11111111-2222-3333-4444-555555555555 -b' "$test_root/simulator-commands" || failures=$((failures + 1))
expect_failure "simulator preparer fails when device is unavailable" "available simulator not found" env \
  PATH="$simulator_bin:$PATH" \
  GITHUB_ENV="$test_root/missing-simulator.env" \
  FLUKE_SIMULATOR_NAME="iPhone Missing" \
  FLUKE_SIMULATOR_LIST_JSON="$test_root/simulators.json" \
  FLUKE_SIMULATOR_COMMAND_CAPTURE="$test_root/simulator-commands" \
  "$simulator_preparer"

recovery_capture="$test_root/simulator-recovery-commands"
expect_success "simulator preparer bounds boot and performs one recovery" env \
  PATH="$simulator_bin:$PATH" \
  GITHUB_ENV="$test_root/recovery-simulator.env" \
  FLUKE_SIMULATOR_LIST_JSON="$test_root/simulators.json" \
  FLUKE_SIMULATOR_COMMAND_CAPTURE="$recovery_capture" \
  FLUKE_SIMULATOR_BOOTSTATUS_MODE="recover-once" \
  FLUKE_SIMULATOR_BOOTSTATUS_COUNT="$test_root/recovery-count" \
  FLUKE_SIMULATOR_BOOT_TIMEOUT_SECONDS="0.05" \
  "$simulator_preparer"
grep -Fxq 'simctl shutdown 11111111-2222-3333-4444-555555555555' "$recovery_capture" \
  || failures=$((failures + 1))
if [[ "$(grep -Fxc 'simctl boot 11111111-2222-3333-4444-555555555555' "$recovery_capture")" != "2" ]]; then
  echo "FAIL: simulator preparer did not perform exactly one reboot" >&2
  failures=$((failures + 1))
fi
expect_failure "simulator preparer fails after one bounded recovery" \
  "simulator failed to boot after one recovery" env \
  PATH="$simulator_bin:$PATH" \
  GITHUB_ENV="$test_root/timeout-simulator.env" \
  FLUKE_SIMULATOR_LIST_JSON="$test_root/simulators.json" \
  FLUKE_SIMULATOR_COMMAND_CAPTURE="$test_root/simulator-timeout-commands" \
  FLUKE_SIMULATOR_BOOTSTATUS_MODE="always-timeout" \
  FLUKE_SIMULATOR_BOOT_TIMEOUT_SECONDS="0.05" \
  "$simulator_preparer"

cat >"$test_root/swift-coverage.json" <<'JSON'
{"data":[{"files":[
  {"filename":"/checkout/Packages/FlukeKit/Sources/FlukeKit/API/APIClient.swift","summary":{"lines":{"count":100,"covered":80}}},
  {"filename":"/checkout/Packages/FlukeKit/Tests/FlukeKitTests/APIClientTests.swift","summary":{"lines":{"count":1000,"covered":1000}}},
  {"filename":"/checkout/Packages/FlukeFeatures/Sources/FlukeFeatures/Sightings/SightingsViewModel.swift","summary":{"lines":{"count":100,"covered":80}}},
  {"filename":"/checkout/Packages/FlukeFeatures/Sources/FlukeFeatures/Sightings/SightingsView.swift","summary":{"lines":{"count":100,"covered":0}}},
  {"filename":"/checkout/Packages/FlukeFeatures/Sources/FlukeFeatures/Learn/LearnContent.swift","summary":{"lines":{"count":10,"covered":10}}}
]}]}
JSON
expect_success "Swift source coverage accepts exact threshold" \
  "$swift_coverage_verifier" "$test_root/swift-coverage.json" /Sources/FlukeKit/ 80
expect_failure "Swift source coverage excludes tests" "below required 80.01%" \
  "$swift_coverage_verifier" "$test_root/swift-coverage.json" /Sources/FlukeKit/ 80.01
expect_failure "Swift source coverage rejects missing sources" "coverage source path not found" \
  "$swift_coverage_verifier" "$test_root/swift-coverage.json" /Sources/Missing/ 80
expect_success "Swift source coverage applies include and exclude selection" \
  "$swift_coverage_verifier" "$test_root/swift-coverage.json" 80 \
  --include '/Sources/FlukeFeatures/.*\.swift$' \
  --exclude '/SightingsView\.swift$'
expect_failure "Swift selected coverage enforces the aggregate threshold" \
  "below required 81.83%" \
  "$swift_coverage_verifier" "$test_root/swift-coverage.json" 81.83 \
  --include '/Sources/FlukeFeatures/.*\.swift$' \
  --exclude '/SightingsView\.swift$'
expect_failure "Swift selected coverage rejects an empty selection" \
  "coverage selection matched no source files" \
  "$swift_coverage_verifier" "$test_root/swift-coverage.json" 80 \
  --include '/Sources/FlukeFeatures/DoesNotExist\.swift$'

archive_path="$test_root/Fluke.xcarchive"
python3 - "$archive_path" <<'PY'
import os
import plistlib
import stat
import sys

archive = sys.argv[1]
app = os.path.join(archive, "Products", "Applications", "Fluke.app")
os.makedirs(app)
with open(os.path.join(archive, "Info.plist"), "wb") as output:
    plistlib.dump(
        {
            "ApplicationProperties": {
                "ApplicationPath": "Applications/Fluke.app",
                "CFBundleIdentifier": "app.fluke.Fluke",
                "CFBundleShortVersionString": "1.0",
                "CFBundleVersion": "1",
            },
            "ArchiveVersion": 2,
            "Name": "Fluke",
            "SchemeName": "Fluke",
        },
        output,
    )
with open(os.path.join(app, "Info.plist"), "wb") as output:
    plistlib.dump(
        {
            "CFBundleExecutable": "Fluke",
            "CFBundleIdentifier": "app.fluke.Fluke",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "DTPlatformName": "iphoneos",
            "MinimumOSVersion": "17.0",
            "UIDeviceFamily": [1],
            "ITSAppUsesNonExemptEncryption": False,
        },
        output,
    )
with open(os.path.join(app, "PrivacyInfo.xcprivacy"), "wb") as output:
    plistlib.dump(
        {
            "NSPrivacyTracking": False,
            "NSPrivacyTrackingDomains": [],
            "NSPrivacyCollectedDataTypes": [],
            "NSPrivacyAccessedAPITypes": [],
        },
        output,
    )
resource_bundle = os.path.join(app, "FlukeFeatures_FlukeFeatures.bundle")
os.makedirs(resource_bundle)
with open(os.path.join(resource_bundle, "OFL.txt"), "w", encoding="utf-8") as output:
    output.write(
        "Copyright 2020 The Fraunces Project Authors\n"
        "SIL OPEN FONT LICENSE Version 1.1\n"
        "PERMISSION & CONDITIONS\n"
        'THE FONT SOFTWARE IS PROVIDED "AS IS"\n'
    )
binary = os.path.join(app, "Fluke")
with open(binary, "wb") as output:
    output.write(b"unsigned-test-binary")
os.chmod(binary, os.stat(binary).st_mode | stat.S_IXUSR)
PY
expect_success "valid unsigned iPhone archive passes" \
  "$archive_verifier" "$archive_path" app.fluke.Fluke 17.0
expect_success "valid archive bundles App Store privacy and font notices" \
  "$app_store_archive_verifier" "$archive_path"
rm "$archive_path/Products/Applications/Fluke.app/PrivacyInfo.xcprivacy"
expect_failure "App Store archive verifier rejects a missing privacy manifest" \
  "archived app is missing PrivacyInfo.xcprivacy" \
  "$app_store_archive_verifier" "$archive_path"
python3 - "$archive_path/Products/Applications/Fluke.app/PrivacyInfo.xcprivacy" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "wb") as output:
    plistlib.dump(
        {
            "NSPrivacyTracking": False,
            "NSPrivacyTrackingDomains": [],
            "NSPrivacyCollectedDataTypes": [],
            "NSPrivacyAccessedAPITypes": [],
        },
        output,
    )
PY
/usr/libexec/PlistBuddy -c 'Set :ApplicationProperties:CFBundleIdentifier app.fluke.Other' \
  "$archive_path/Info.plist"
expect_failure "wrong archive bundle identifier fails" "bundle identifier mismatch" \
  "$archive_verifier" "$archive_path" app.fluke.Fluke 17.0

fake_bin="$test_root/bin"
mkdir -p "$fake_bin"
cat >"$fake_bin/xcodebuild" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$FLUKE_XCODEBUILD_CAPTURE"
SH
chmod +x "$fake_bin/xcodebuild"
capture="$test_root/xcodebuild-arguments"
expect_success "boundary verifier accepts result and coverage options" env \
  PATH="$fake_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  FLUKE_XCODEBUILD_CAPTURE="$capture" \
  FLUKE_TEST_DESTINATION="platform=iOS Simulator,name=Verifier" \
  FLUKE_RESULT_BUNDLE_PATH="$test_root/AppTests.xcresult" \
  FLUKE_ENABLE_COVERAGE=YES \
  "$boundary_verifier"

invalid_icon="$test_root/invalid-icon.png"
printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL6WQAAAABJRU5ErkJggg==' \
  | base64 -D >"$invalid_icon"
expect_failure "boundary verifier rejects an invalid App Store icon" \
  "App Store icon must be an opaque 1024x1024 PNG" env \
  PATH="$fake_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  FLUKE_XCODEBUILD_CAPTURE="$capture" \
  FLUKE_APP_ICON_PATH="$invalid_icon" \
  "$boundary_verifier"

app_store_fixture="$test_root/app-store"
mkdir -p "$app_store_fixture/metadata/en-US" "$app_store_fixture/Fonts"
cp "$repo_root/App/Fluke/Assets.xcassets/AppIcon.appiconset/icon-1024.png" \
  "$app_store_fixture/icon-1024.png"
cat >"$app_store_fixture/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>ITSAppUsesNonExemptEncryption</key><false/>
</dict></plist>
PLIST
cat >"$app_store_fixture/PrivacyInfo.xcprivacy" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>NSPrivacyTracking</key><false/>
<key>NSPrivacyTrackingDomains</key><array/>
<key>NSPrivacyCollectedDataTypes</key><array/>
<key>NSPrivacyAccessedAPITypes</key><array/>
</dict></plist>
PLIST
cat >"$app_store_fixture/Fonts/OFL.txt" <<'TEXT'
Copyright 2020 The Fraunces Project Authors (github.com/undercasetype/Fraunces)
SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007
PERMISSION & CONDITIONS
THE FONT SOFTWARE IS PROVIDED "AS IS"
TEXT
cat >"$app_store_fixture/metadata/en-US/metadata.json" <<'JSON'
{
  "version": "1.0",
  "name": "Fluke",
  "subtitle": "Explore PNW orcas",
  "description": "Browse public sightings, learn about cataloged whales, read field notes, and explore an evidence-based atlas. Release A is read-only.",
  "keywords": "orca,sightings,Salish Sea,whale catalog,wildlife,marine biology",
  "promotionalText": "Explore public Pacific Northwest orca records with clear source context.",
  "whatsNew": "Initial TestFlight release.",
  "supportURL": "https://fluke-pnw.vercel.app/support",
  "privacyURL": "https://fluke-pnw.vercel.app/privacy",
  "marketingURL": "https://fluke-pnw.vercel.app",
  "copyright": "2026 Cale Lamb",
  "reviewNotes": "No account is required. Release A is read-only and has four tabs: Sightings, Whales, Learn, and Atlas."
}
JSON
expect_success "App Store release verifier accepts complete launch assets" env \
  FLUKE_INFO_PLIST="$app_store_fixture/Info.plist" \
  FLUKE_PRIVACY_MANIFEST="$app_store_fixture/PrivacyInfo.xcprivacy" \
  FLUKE_APP_STORE_METADATA="$app_store_fixture/metadata/en-US/metadata.json" \
  FLUKE_APP_ICON_PATH="$app_store_fixture/icon-1024.png" \
  FLUKE_FONT_LICENSE_PATH="$app_store_fixture/Fonts/OFL.txt" \
  "$app_store_verifier"
/usr/libexec/PlistBuddy -c 'Set :ITSAppUsesNonExemptEncryption true' \
  "$app_store_fixture/Info.plist"
expect_failure "App Store release verifier rejects incorrect export compliance" \
  "ITSAppUsesNonExemptEncryption must be false" env \
  FLUKE_INFO_PLIST="$app_store_fixture/Info.plist" \
  FLUKE_PRIVACY_MANIFEST="$app_store_fixture/PrivacyInfo.xcprivacy" \
  FLUKE_APP_STORE_METADATA="$app_store_fixture/metadata/en-US/metadata.json" \
  FLUKE_APP_ICON_PATH="$app_store_fixture/icon-1024.png" \
  FLUKE_FONT_LICENSE_PATH="$app_store_fixture/Fonts/OFL.txt" \
  "$app_store_verifier"
/usr/libexec/PlistBuddy -c 'Set :ITSAppUsesNonExemptEncryption false' \
  "$app_store_fixture/Info.plist"
python3 - "$app_store_fixture/metadata/en-US/metadata.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as source:
    metadata = json.load(source)
metadata["keywords"] = "x" * 101
with open(path, "w", encoding="utf-8") as output:
    json.dump(metadata, output)
PY
expect_failure "App Store release verifier enforces keyword byte limit" \
  "keywords exceeds 100 UTF-8 bytes" env \
  FLUKE_INFO_PLIST="$app_store_fixture/Info.plist" \
  FLUKE_PRIVACY_MANIFEST="$app_store_fixture/PrivacyInfo.xcprivacy" \
  FLUKE_APP_STORE_METADATA="$app_store_fixture/metadata/en-US/metadata.json" \
  FLUKE_APP_ICON_PATH="$app_store_fixture/icon-1024.png" \
  FLUKE_FONT_LICENSE_PATH="$app_store_fixture/Fonts/OFL.txt" \
  "$app_store_verifier"

screenshot_fixture="$test_root/screenshots"
mkdir -p "$screenshot_fixture"
sips --resampleHeightWidth 2736 1260 \
  "$repo_root/App/Fluke/Assets.xcassets/AppIcon.appiconset/icon-1024.png" \
  --out "$screenshot_fixture/01-sightings.png" >/dev/null
expect_success "screenshot verifier accepts a 6.9-inch portrait set" \
  "$screenshot_verifier" "$screenshot_fixture"
cp "$repo_root/App/Fluke/Assets.xcassets/AppIcon.appiconset/icon-1024.png" \
  "$screenshot_fixture/02-invalid.png"
expect_failure "screenshot verifier rejects an unsupported size" \
  "unsupported iPhone screenshot size" \
  "$screenshot_verifier" "$screenshot_fixture"
rm "$screenshot_fixture/02-invalid.png"
python3 - "$screenshot_fixture/02-black-band.png" <<'PY'
import sys
import subprocess
import tempfile

with tempfile.NamedTemporaryFile(suffix=".ppm") as source:
    source.write(b"P6\n1260 2736\n255\n")
    source.write(b"\0" * (1260 * 2736 * 3))
    source.flush()
    subprocess.run(
        ["sips", "-s", "format", "png", source.name, "--out", sys.argv[1]],
        check=True,
        stdout=subprocess.DEVNULL,
    )
PY
expect_failure "screenshot verifier rejects an excessive near-black band" \
  "screenshot contains an excessive near-black band" \
  "$screenshot_verifier" "$screenshot_fixture"
rm "$screenshot_fixture/02-black-band.png"

capture_bin="$test_root/capture-bin"
capture_output="$test_root/captured-screenshots"
mkdir -p "$capture_bin"
cat >"$capture_bin/xcodebuild" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$FLUKE_CAPTURE_XCODEBUILD_CAPTURE"
exit 0
SH
cat >"$capture_bin/curl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$FLUKE_CAPTURE_CURL_CAPTURE"
exit 0
SH
cat >"$capture_bin/xcrun" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$FLUKE_CAPTURE_SIMCTL_CAPTURE"
if [[ "$*" == "simctl list devices available --json" ]]; then
  cat <<'JSON'
{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-0":[
  {"name":"iPhone 17 Pro Max","udid":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","isAvailable":true}
]}}
JSON
  exit 0
fi
if [[ "$1 $2" == "simctl bootstatus" && "${FLUKE_SIMULATOR_BOOTSTATUS_MODE:-}" == "recover-once" ]]; then
  count="$(cat "${FLUKE_SIMULATOR_BOOTSTATUS_COUNT}" 2>/dev/null || printf 0)"
  printf '%s' "$((count + 1))" >"$FLUKE_SIMULATOR_BOOTSTATUS_COUNT"
  if [[ "$count" == "0" ]]; then
    sleep 1
  fi
  exit 0
fi
if [[ "$1 $2" == "simctl boot" || "$1 $2" == "simctl shutdown" ]]; then
  exit 0
fi
if [[ "$1 $2" == "simctl status_bar" ]]; then
  exit 0
fi
if [[ "$1 $2 $3" == "xcresulttool export attachments" ]]; then
  while (($#)); do
    if [[ "$1" == "--output-path" ]]; then
      output_path="$2"
      break
    fi
    shift
  done
  mkdir -p "$output_path"
  for name in 01-sightings 02-whales 03-learn 04-atlas; do
    cp "$FLUKE_SCREENSHOT_FIXTURE" "$output_path/$name.png"
  done
  cat >"$output_path/manifest.json" <<'JSON'
[{"testIdentifier":"capture","attachments":[
  {"suggestedHumanReadableName":"01-sightings_0_AAAAAAAA.png","exportedFileName":"01-sightings.png"},
  {"suggestedHumanReadableName":"02-whales_0_BBBBBBBB.png","exportedFileName":"02-whales.png"},
  {"suggestedHumanReadableName":"03-learn_0_CCCCCCCC.png","exportedFileName":"03-learn.png"},
  {"suggestedHumanReadableName":"04-atlas_0_DDDDDDDD.png","exportedFileName":"04-atlas.png"}
]}]
JSON
  exit 0
fi
printf 'unexpected xcrun command: %s\n' "$*" >&2
exit 1
SH
chmod +x "$capture_bin/curl" "$capture_bin/xcodebuild" "$capture_bin/xcrun"
expect_success "screenshot capture resolves a pinned simulator and exports named images" env \
  PATH="$capture_bin:$PATH" \
  FLUKE_SCREENSHOT_FIXTURE="$screenshot_fixture/01-sightings.png" \
  FLUKE_CAPTURE_XCODEBUILD_CAPTURE="$test_root/capture-xcodebuild-arguments" \
  FLUKE_CAPTURE_CURL_CAPTURE="$test_root/capture-curl-arguments" \
  FLUKE_CAPTURE_SIMCTL_CAPTURE="$test_root/capture-simctl-arguments" \
  FLUKE_SIMULATOR_BOOTSTATUS_MODE="recover-once" \
  FLUKE_SIMULATOR_BOOTSTATUS_COUNT="$test_root/capture-recovery-count" \
  FLUKE_SIMULATOR_BOOT_TIMEOUT_SECONDS="0.05" \
  "$screenshot_capture" "$capture_output"
if [[ "$(find "$capture_output" -type f -name '*.png' | wc -l | tr -d ' ')" != "4" ]]; then
  echo "FAIL: screenshot capture did not export four named images" >&2
  failures=$((failures + 1))
fi
if ! grep -Fxq -- 'simctl shutdown AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE' \
  "$test_root/capture-simctl-arguments"; then
  echo "FAIL: screenshot capture did not use bounded simulator recovery" >&2
  failures=$((failures + 1))
fi
if ! grep -Fxq -- 'https://fluke-api.onrender.com/api/v1/health' "$test_root/capture-curl-arguments"; then
  echo "FAIL: screenshot capture did not warm the production API" >&2
  failures=$((failures + 1))
fi
if ! grep -Fxq -- '-configuration' "$test_root/capture-xcodebuild-arguments" \
  || ! grep -Fxq -- 'Release' "$test_root/capture-xcodebuild-arguments" \
  || ! grep -Fxq -- 'ENABLE_TESTABILITY=YES' "$test_root/capture-xcodebuild-arguments"; then
  echo "FAIL: screenshot capture did not use the live Release configuration" >&2
  failures=$((failures + 1))
fi
if ! grep -Fxq -- '-resultBundlePath' "$capture" \
  || ! grep -Fxq -- "$test_root/AppTests.xcresult" "$capture" \
  || ! grep -Fxq -- '-enableCodeCoverage' "$capture" \
  || ! grep -Fxq -- '-parallel-testing-enabled' "$capture" \
  || ! grep -Fxq -- '-maximum-concurrent-test-simulator-destinations' "$capture" \
  || ! grep -Fxq -- 'YES' "$capture"; then
  printf 'FAIL: boundary verifier did not forward result/coverage arguments\n' >&2
  failures=$((failures + 1))
fi

boundary_sources="$test_root/boundary-sources"
feature_sources="$test_root/feature-sources"
mkdir -p "$boundary_sources"
mkdir -p "$feature_sources"
printf 'let shippingViews = [SightingsView.self, WhalesView.self, LearnView.self, AtlasView.self]\n' \
  >"$boundary_sources/AllowedPersistence.swift"
printf 'struct AtlasFeatureItem {}\n' >"$feature_sources/AllowedFeature.swift"
expect_success "boundary verifier allows ordinary persistence names" env \
  PATH="$fake_bin:$PATH" \
  FLUKE_XCODEBUILD_CAPTURE="$capture" \
  FLUKE_APP_SOURCE_ROOT="$boundary_sources" \
  FLUKE_FEATURE_SOURCE_ROOT="$feature_sources" \
  "$boundary_verifier"
sed -i '' 's/AtlasView/AtlasMissing/' "$boundary_sources/AllowedPersistence.swift"
expect_failure "boundary verifier requires every real shipping view" \
  "Missing Release A shipping view: AtlasView" env \
  PATH="$fake_bin:$PATH" \
  FLUKE_XCODEBUILD_CAPTURE="$capture" \
  FLUKE_APP_SOURCE_ROOT="$boundary_sources" \
  FLUKE_FEATURE_SOURCE_ROOT="$feature_sources" \
  "$boundary_verifier"
sed -i '' 's/AtlasMissing/AtlasView/' "$boundary_sources/AllowedPersistence.swift"
printf 'struct SubmitView {}\n' >"$boundary_sources/ReleaseB.swift"
expect_failure "boundary verifier rejects Release B presentation" \
  "Release A boundary violation" env \
  PATH="$fake_bin:$PATH" \
  FLUKE_XCODEBUILD_CAPTURE="$capture" \
  FLUKE_APP_SOURCE_ROOT="$boundary_sources" \
  FLUKE_FEATURE_SOURCE_ROOT="$feature_sources" \
  "$boundary_verifier"
rm "$boundary_sources/ReleaseB.swift"
printf 'import FlukeReleaseB\nlet response: IdentifyResponse?\n' >"$feature_sources/ReleaseBImport.swift"
expect_failure "boundary verifier rejects Release B feature imports" \
  "Release B compile boundary violation" env \
  PATH="$fake_bin:$PATH" \
  FLUKE_XCODEBUILD_CAPTURE="$capture" \
  FLUKE_APP_SOURCE_ROOT="$boundary_sources" \
  FLUKE_FEATURE_SOURCE_ROOT="$feature_sources" \
  "$boundary_verifier"
rm "$feature_sources/ReleaseBImport.swift"
printf 'struct SightingsPlaceholder {}\n' >"$feature_sources/SightingsPlaceholder.swift"
expect_failure "boundary verifier rejects shipping placeholder surfaces" \
  "Release A placeholder boundary violation" env \
  PATH="$fake_bin:$PATH" \
  FLUKE_XCODEBUILD_CAPTURE="$capture" \
  FLUKE_APP_SOURCE_ROOT="$boundary_sources" \
  FLUKE_FEATURE_SOURCE_ROOT="$feature_sources" \
  "$boundary_verifier"
rm "$feature_sources/SightingsPlaceholder.swift"

configuration_root="$test_root/configuration"
mkdir -p "$configuration_root"
printf 'FLUKE_API_BASE_URL = http:/$()/localhost:4000\n' >"$configuration_root/Debug.xcconfig"
printf 'FLUKE_API_BASE_URL = https:/$()/staging-api.fluke.invalid\n' >"$configuration_root/Staging.xcconfig"
printf 'FLUKE_API_BASE_URL = https:/$()/api.fluke.invalid\n' >"$configuration_root/Release.xcconfig"
expect_failure "boundary verifier rejects placeholder Release API origins" \
  "Release API origin must be https://fluke-api.onrender.com" env \
  PATH="$fake_bin:$PATH" \
  FLUKE_XCODEBUILD_CAPTURE="$capture" \
  FLUKE_APP_SOURCE_ROOT="$boundary_sources" \
  FLUKE_FEATURE_SOURCE_ROOT="$feature_sources" \
  FLUKE_CONFIGURATION_ROOT="$configuration_root" \
  "$boundary_verifier"
printf 'FLUKE_API_BASE_URL = https:/$()/fluke-api.onrender.com\n' >"$configuration_root/Release.xcconfig"
expect_success "boundary verifier accepts the certified Release API origin" env \
  PATH="$fake_bin:$PATH" \
  FLUKE_XCODEBUILD_CAPTURE="$capture" \
  FLUKE_APP_SOURCE_ROOT="$boundary_sources" \
  FLUKE_FEATURE_SOURCE_ROOT="$feature_sources" \
  FLUKE_CONFIGURATION_ROOT="$configuration_root" \
  "$boundary_verifier"

documentation_root="$test_root/documentation"
mkdir -p "$documentation_root/docs"
for documentation_path in README.md docs/architecture.md docs/build-and-ci.md docs/testing.md; do
  printf 'Release A has four browse tabs.\n' >"$documentation_root/$documentation_path"
done
printf 'Five tabs are currently released.\n' >"$documentation_root/README.md"
expect_failure "boundary verifier rejects stale release documentation" \
  "Stale Release A documentation" env \
  PATH="$fake_bin:$PATH" \
  FLUKE_XCODEBUILD_CAPTURE="$capture" \
  FLUKE_APP_SOURCE_ROOT="$boundary_sources" \
  FLUKE_FEATURE_SOURCE_ROOT="$feature_sources" \
  FLUKE_DOCUMENTATION_ROOT="$documentation_root" \
  "$boundary_verifier"

default_capture="$test_root/xcodebuild-default-arguments"
expect_success "boundary verifier accepts omitted result path" env \
  PATH="$fake_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  FLUKE_XCODEBUILD_CAPTURE="$default_capture" \
  FLUKE_TEST_DESTINATION="platform=iOS Simulator,name=Verifier" \
  "$boundary_verifier"
if grep -Fxq -- '-resultBundlePath' "$default_capture"; then
  printf 'FAIL: boundary verifier forwarded an empty result path\n' >&2
  failures=$((failures + 1))
fi

if ((failures > 0)); then
  printf '%d verification script test(s) failed\n' "$failures" >&2
  exit 1
fi

printf 'All verification script tests passed\n'
