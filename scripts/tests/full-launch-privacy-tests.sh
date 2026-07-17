#!/usr/bin/env bash

set -u

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
verifier="$repo_root/scripts/verify-full-launch-privacy.sh"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/fluke-privacy-tests.XXXXXX")"
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
  local expected="$2"
  shift 2
  if output="$("$@" 2>&1)"; then
    printf 'FAIL: %s unexpectedly succeeded\n' "$name" >&2
    failures=$((failures + 1))
  elif [[ "$output" != *"$expected"* ]]; then
    printf 'FAIL: %s did not report %q\n%s\n' "$name" "$expected" "$output" >&2
    failures=$((failures + 1))
  fi
}

make_fixture() {
  local root="$1"
  mkdir -p "$root/App/Fluke"
  cp "$repo_root/App/Fluke/Info.plist" "$root/App/Fluke/Info.plist"
  cp "$repo_root/App/Fluke/Fluke.entitlements" "$root/App/Fluke/Fluke.entitlements"
  cp "$repo_root/App/Fluke/PrivacyInfo.xcprivacy" "$root/App/Fluke/PrivacyInfo.xcprivacy"
}

valid="$test_root/valid"
make_fixture "$valid"
expect_success "shipping privacy contract passes" "$verifier" --root "$valid"

location="$test_root/location"
make_fixture "$location"
plutil -insert NSLocationWhenInUseUsageDescription -string "Find you" "$location/App/Fluke/Info.plist"
expect_failure "location permission copy is rejected" "location permission descriptions must be absent" \
  "$verifier" --root "$location"

ats="$test_root/ats"
make_fixture "$ats"
plutil -insert NSAppTransportSecurity -xml '<dict><key>NSAllowsArbitraryLoads</key><true/></dict>' \
  "$ats/App/Fluke/Info.plist"
expect_failure "disabled ATS is rejected" "ATS must remain enabled" "$verifier" --root "$ats"

tracking="$test_root/tracking"
make_fixture "$tracking"
plutil -replace NSPrivacyTracking -bool YES "$tracking/App/Fluke/PrivacyInfo.xcprivacy"
expect_failure "tracking is rejected" "tracking must be false" "$verifier" --root "$tracking"

missing_category="$test_root/missing-category"
make_fixture "$missing_category"
python3 - "$missing_category/App/Fluke/PrivacyInfo.xcprivacy" <<'PY'
import plistlib
import sys

path = sys.argv[1]
with open(path, "rb") as source:
    manifest = plistlib.load(source)
manifest["NSPrivacyCollectedDataTypes"] = manifest["NSPrivacyCollectedDataTypes"][:-1]
with open(path, "wb") as output:
    plistlib.dump(manifest, output)
PY
expect_failure "missing linked-data category is rejected" "exact linked-data categories" \
  "$verifier" --root "$missing_category"

att="$test_root/att"
make_fixture "$att"
plutil -insert NSUserTrackingUsageDescription -string "Track" "$att/App/Fluke/Info.plist"
expect_failure "ATT usage is rejected" "ATT usage description must be absent" "$verifier" --root "$att"

if ((failures > 0)); then
  printf '%d full-launch privacy verifier test(s) failed\n' "$failures" >&2
  exit 1
fi

printf 'full-launch privacy verifier tests passed\n'
