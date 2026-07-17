#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project="$repo_root/App/Fluke.xcodeproj"
destination="${FLUKE_TEST_DESTINATION:-platform=iOS Simulator,name=iPhone 17,OS=26.0.1}"
result_bundle_path="${FLUKE_RESULT_BUNDLE_PATH:-}"
enable_coverage="${FLUKE_ENABLE_COVERAGE:-NO}"

if [[ "$enable_coverage" != "YES" && "$enable_coverage" != "NO" ]]; then
  echo "FLUKE_ENABLE_COVERAGE must be YES or NO" >&2
  exit 2
fi

if rg -n 'SwiftData|\bItem\b|IdentifyPlaceholder|YouPlaceholder|Submit' \
  "$repo_root/App/Fluke"; then
  echo "Release A boundary violation in the app target" >&2
  exit 1
fi

for module in FlukeKit FlukeUI FlukeFeatures; do
  rg -q "productName = $module" "$project/project.pbxproj" || {
    echo "Missing app package product: $module" >&2
    exit 1
  }
done

for configuration in Debug Staging Release; do
  test -f "$repo_root/App/Configuration/$configuration.xcconfig" || {
    echo "Missing $configuration.xcconfig" >&2
    exit 1
  }
done

test -f "$project/xcshareddata/xcschemes/Fluke.xcscheme" || {
  echo "Missing shared Fluke scheme" >&2
  exit 1
}

result_arguments=()
if [[ -n "$result_bundle_path" ]]; then
  result_arguments=(-resultBundlePath "$result_bundle_path")
fi

xcodebuild test \
  -project "$project" \
  -scheme Fluke \
  -destination "$destination" \
  -only-testing:FlukeTests \
  -enableCodeCoverage "$enable_coverage" \
  "${result_arguments[@]}" \
  CODE_SIGNING_ALLOWED=NO
