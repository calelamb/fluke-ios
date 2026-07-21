#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project="$repo_root/App/Fluke.xcodeproj"
app_source_root="${FLUKE_APP_SOURCE_ROOT:-$repo_root/App/Fluke}"
feature_source_root="${FLUKE_FEATURE_SOURCE_ROOT:-$repo_root/Packages/FlukeFeatures/Sources}"
ui_source_root="${FLUKE_UI_SOURCE_ROOT:-$repo_root/Packages/FlukeUI/Sources}"
documentation_root="${FLUKE_DOCUMENTATION_ROOT:-$repo_root}"
configuration_root="${FLUKE_CONFIGURATION_ROOT:-$repo_root/App/Configuration}"
app_icon_path="${FLUKE_APP_ICON_PATH:-$repo_root/App/Fluke/Assets.xcassets/AppIcon.appiconset/icon-1024.png}"
destination="${FLUKE_TEST_DESTINATION:-platform=iOS Simulator,name=iPhone 17,OS=26.0.1}"
result_bundle_path="${FLUKE_RESULT_BUNDLE_PATH:-}"
enable_coverage="${FLUKE_ENABLE_COVERAGE:-NO}"

search_lines() {
  local pattern="$1"
  local path="$2"
  if command -v rg >/dev/null 2>&1; then
    rg -n -- "$pattern" "$path"
  else
    grep -ERn -- "$pattern" "$path"
  fi
}

contains_pattern() {
  local pattern="$1"
  local path="$2"
  if command -v rg >/dev/null 2>&1; then
    rg -q -- "$pattern" "$path"
  else
    grep -ERq -- "$pattern" "$path"
  fi
}

if [[ "$enable_coverage" != "YES" && "$enable_coverage" != "NO" ]]; then
  echo "FLUKE_ENABLE_COVERAGE must be YES or NO" >&2
  exit 2
fi

test -f "$app_icon_path" || {
  echo "Missing 1024-point app icon" >&2
  exit 1
}
icon_width="$(sips -g pixelWidth "$app_icon_path" | awk '/pixelWidth/{print $2}')"
icon_height="$(sips -g pixelHeight "$app_icon_path" | awk '/pixelHeight/{print $2}')"
icon_has_alpha="$(sips -g hasAlpha "$app_icon_path" | awk '/hasAlpha/{print $2}')"
if [[ "$icon_width" != "1024" || "$icon_height" != "1024" || "$icon_has_alpha" != "no" ]]; then
  echo "App Store icon must be an opaque 1024x1024 PNG" >&2
  exit 1
fi

for shipping_view in SightingsView WhalesView IdentifyView LearnView YouView AtlasView; do
  if ! contains_pattern "(^|[^[:alnum:]_])${shipping_view}([^[:alnum:]_]|$)" "$app_source_root"; then
    echo "Missing full-launch shipping view: $shipping_view" >&2
    exit 1
  fi
done

if ! contains_pattern 'FlukeReleaseB' "$repo_root/Packages/FlukeFeatures/Package.swift"; then
  echo "Missing full-launch FlukeReleaseB dependency" >&2
  exit 1
fi

if search_lines 'PlaceholderScreen|(^|[^[:alnum:]_])[[:alnum:]_]+Placeholder([^[:alnum:]_]|$)' \
  "$feature_source_root" \
  || search_lines 'PlaceholderScreen' "$ui_source_root"; then
  echo "Full-launch placeholder boundary violation" >&2
  exit 1
fi

documentation_paths=(
  "$documentation_root/README.md"
  "$documentation_root/docs/architecture.md"
  "$documentation_root/docs/build-and-ci.md"
  "$documentation_root/docs/testing.md"
)
for documentation_path in "${documentation_paths[@]}"; do
  test -f "$documentation_path" || {
    echo "Missing full-launch documentation: $documentation_path" >&2
    exit 1
  }
  if search_lines 'Five tabs|The 5-tab|all 5 tabs|AllFiveTabs|identify-tab placeholder|sign in \(mocked\)|Submit sheet|M-iOS-7 brings|Xcode 16|Node 20|pnpm 9|OS=latest|api\.fluke\.invalid|supply a real production API origin' \
    "$documentation_path"; then
    echo "Stale full-launch documentation" >&2
    exit 1
  fi
done

for module in FlukeKit FlukeUI FlukeFeatures; do
  contains_pattern "productName = $module" "$project/project.pbxproj" || {
    echo "Missing app package product: $module" >&2
    exit 1
  }
done

for configuration in Debug Staging Release; do
  test -f "$configuration_root/$configuration.xcconfig" || {
    echo "Missing $configuration.xcconfig" >&2
    exit 1
  }
done

release_api_setting='FLUKE_API_BASE_URL = https:/$()/fluke-api.onrender.com'
if ! grep -Fxq -- "$release_api_setting" "$configuration_root/Release.xcconfig"; then
  echo "Release API origin must be https://fluke-api.onrender.com" >&2
  exit 1
fi

test -f "$project/xcshareddata/xcschemes/Fluke.xcscheme" || {
  echo "Missing shared Fluke scheme" >&2
  exit 1
}

xcodebuild_arguments=(
  test
  -project "$project"
  -scheme Fluke
  -destination "$destination"
  -only-testing:FlukeTests
  -only-testing:FlukeUITests/FlukeUITests/testPublicBrowseTabsAreReachable
  -parallel-testing-enabled NO
  -maximum-concurrent-test-simulator-destinations 1
  -enableCodeCoverage "$enable_coverage"
)
if [[ -n "$result_bundle_path" ]]; then
  xcodebuild_arguments+=(-resultBundlePath "$result_bundle_path")
fi
xcodebuild_arguments+=(CODE_SIGNING_ALLOWED=NO)

echo "Full launch iOS verification"
xcodebuild "${xcodebuild_arguments[@]}"
