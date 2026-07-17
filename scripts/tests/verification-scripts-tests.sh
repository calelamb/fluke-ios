#!/usr/bin/env bash

set -u

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture_verifier="$repo_root/scripts/verify-contract-fixtures.sh"
coverage_verifier="$repo_root/scripts/verify-coverage.sh"
archive_verifier="$repo_root/scripts/verify-archive-metadata.sh"
boundary_verifier="$repo_root/scripts/verify-release-a-boundaries.sh"
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
        },
        output,
    )
binary = os.path.join(app, "Fluke")
with open(binary, "wb") as output:
    output.write(b"unsigned-test-binary")
os.chmod(binary, os.stat(binary).st_mode | stat.S_IXUSR)
PY
expect_success "valid unsigned iPhone archive passes" \
  "$archive_verifier" "$archive_path" app.fluke.Fluke 17.0
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
if ! grep -Fxq -- '-resultBundlePath' "$capture" \
  || ! grep -Fxq -- "$test_root/AppTests.xcresult" "$capture" \
  || ! grep -Fxq -- '-enableCodeCoverage' "$capture" \
  || ! grep -Fxq -- 'YES' "$capture"; then
  printf 'FAIL: boundary verifier did not forward result/coverage arguments\n' >&2
  failures=$((failures + 1))
fi

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
