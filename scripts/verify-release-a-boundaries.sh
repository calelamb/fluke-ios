#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project="$repo_root/App/Fluke.xcodeproj"
destination="${FLUKE_TEST_DESTINATION:-platform=iOS Simulator,name=iPhone 17,OS=26.0.1}"

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

xcodebuild test \
  -project "$project" \
  -scheme Fluke \
  -destination "$destination" \
  -only-testing:FlukeTests \
  CODE_SIGNING_ALLOWED=NO
