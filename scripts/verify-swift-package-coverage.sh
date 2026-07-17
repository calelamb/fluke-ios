#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 3 ]]; then
  printf 'usage: %s <codecov-json> <source-path-fragment> <minimum-percent>\n' "$0" >&2
  exit 2
fi

python3 - "$1" "$2" "$3" <<'PY'
import json
import math
import sys

report_path, source_fragment, threshold_text = sys.argv[1:]

try:
    threshold = float(threshold_text)
except ValueError:
    raise SystemExit("minimum coverage must be numeric")
if not math.isfinite(threshold) or not 0 <= threshold <= 100:
    raise SystemExit("minimum coverage must be between 0 and 100")

try:
    with open(report_path, encoding="utf-8") as source:
        report = json.load(source)
except (OSError, json.JSONDecodeError) as error:
    raise SystemExit(f"unable to read coverage report: {error}")

files = []
for data in report.get("data", []):
    files.extend(data.get("files", []))
matching = [item for item in files if source_fragment in item.get("filename", "")]
if not matching:
    raise SystemExit(f"coverage source path not found: {source_fragment}")

line_counts = [item.get("summary", {}).get("lines", {}) for item in matching]
try:
    executable = sum(int(item["count"]) for item in line_counts)
    covered = sum(int(item["covered"]) for item in line_counts)
except (KeyError, TypeError, ValueError):
    raise SystemExit("coverage report has invalid source line counts")
if executable <= 0 or covered < 0 or covered > executable:
    raise SystemExit("coverage report has inconsistent source line counts")

percent = covered * 100 / executable
if percent + 1e-9 < threshold:
    raise SystemExit(
        f"source line coverage {percent:.2f}% is below required {threshold:.2f}% "
        f"({covered}/{executable})"
    )
print(f"source line coverage {percent:.2f}% ({covered}/{executable})")
PY
