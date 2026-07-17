#!/usr/bin/env bash

set -euo pipefail

if (($# != 3)); then
  printf 'Usage: %s <xccov-report.json> <target-name> <minimum-percent>\n' "$0" >&2
  exit 2
fi

python3 - "$1" "$2" "$3" <<'PY'
import json
import math
import sys

report_path, target_name, minimum_text = sys.argv[1:]
try:
    minimum = float(minimum_text)
except ValueError:
    raise SystemExit(f"Invalid coverage threshold: {minimum_text}")
if not math.isfinite(minimum) or not 0 <= minimum <= 100:
    raise SystemExit(f"Invalid coverage threshold: {minimum_text}")

try:
    with open(report_path, encoding="utf-8") as report_file:
        report = json.load(report_file)
except (OSError, json.JSONDecodeError) as error:
    raise SystemExit(f"Unable to read coverage report: {error}")

targets = [target for target in report.get("targets", []) if target.get("name") == target_name]
if len(targets) != 1:
    raise SystemExit(f"coverage target not found exactly once: {target_name}")

target = targets[0]
try:
    executable = int(target.get("executableLines", 0))
    covered = int(target.get("coveredLines", 0))
    reported_ratio = float(target.get("lineCoverage", 0))
except (TypeError, ValueError) as error:
    raise SystemExit(f"coverage target contains invalid values: {error}")
if executable <= 0:
    raise SystemExit(f"coverage target has no executable lines: {target_name}")
if covered < 0 or covered > executable:
    raise SystemExit("coverage report is inconsistent: invalid covered line count")

calculated_ratio = covered / executable
if not math.isclose(reported_ratio, calculated_ratio, rel_tol=0, abs_tol=1e-9):
    raise SystemExit("coverage report is inconsistent: ratio does not match line counts")
percent = calculated_ratio * 100
if percent + 1e-9 < minimum:
    raise SystemExit(
        f"{target_name} line coverage {percent:.2f}% is below required {minimum:.2f}%"
    )
print(f"{target_name} line coverage {percent:.2f}% ({covered}/{executable})")
PY
