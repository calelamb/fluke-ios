#!/usr/bin/env bash

set -euo pipefail

simulator_name="${FLUKE_SIMULATOR_NAME:-iPhone 17}"
runtime_identifier="${FLUKE_SIMULATOR_RUNTIME_IDENTIFIER:-com.apple.CoreSimulator.SimRuntime.iOS-26-0}"
environment_file="${GITHUB_ENV:-}"

device_json="$(xcrun simctl list devices available --json)"
selection="$(FLUKE_DEVICE_LIST_JSON="$device_json" python3 - "$simulator_name" "$runtime_identifier" <<'PY'
import json
import os
import sys

name, runtime = sys.argv[1:]
devices = json.loads(os.environ["FLUKE_DEVICE_LIST_JSON"]).get("devices", {}).get(runtime, [])
matches = [
    device for device in devices
    if device.get("name") == name and device.get("isAvailable", False)
]
matches.sort(key=lambda device: (device.get("state") != "Booted", device.get("udid", "")))
if matches:
    selected = matches[0]
    print(f"{selected.get('udid', '')}\t{selected.get('state', '')}")
PY
)"

if [[ -z "$selection" ]]; then
  printf 'available simulator not found: %s (%s)\n' "$simulator_name" "$runtime_identifier" >&2
  exit 1
fi

IFS=$'\t' read -r simulator_udid simulator_state <<<"$selection"
if [[ ! "$simulator_udid" =~ ^[0-9A-Fa-f-]{36}$ ]]; then
  printf 'resolved simulator has invalid UDID\n' >&2
  exit 1
fi

if [[ "$simulator_state" != "Booted" ]]; then
  xcrun simctl boot "$simulator_udid"
fi
xcrun simctl bootstatus "$simulator_udid" -b

destination="platform=iOS Simulator,id=$simulator_udid"
if [[ -n "$environment_file" ]]; then
  {
    printf 'SIMULATOR_UDID=%s\n' "$simulator_udid"
    printf 'SIMULATOR_DESTINATION=%s\n' "$destination"
    printf 'FLUKE_TEST_DESTINATION=%s\n' "$destination"
  } >>"$environment_file"
else
  printf 'SIMULATOR_UDID=%s\nSIMULATOR_DESTINATION=%s\nFLUKE_TEST_DESTINATION=%s\n' \
    "$simulator_udid" "$destination" "$destination"
fi
