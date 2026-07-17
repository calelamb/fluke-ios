#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 3 ]]; then
  printf 'usage: %s <codecov-json> <source-path-fragment> <minimum-percent>\n' "$0" >&2
  printf '   or: %s <codecov-json> <minimum-percent> --include <regex> [--include <regex> ...] [--exclude <regex> ...]\n' "$0" >&2
  exit 2
fi

python3 - "$@" <<'PY'
import json
import math
import re
import sys

arguments = sys.argv[1:]
if len(arguments) == 3:
    report_path, source_fragment, threshold_text = arguments
    include_patterns = []
    exclude_patterns = []
    selection_label = source_fragment
else:
    report_path, threshold_text, *selection_arguments = arguments
    include_patterns = []
    exclude_patterns = []
    index = 0
    while index < len(selection_arguments):
        option = selection_arguments[index]
        if option not in ("--include", "--exclude") or index + 1 >= len(selection_arguments):
            raise SystemExit("coverage selection requires --include or --exclude followed by a regex")
        try:
            pattern = re.compile(selection_arguments[index + 1])
        except re.error as error:
            raise SystemExit(f"invalid coverage selection regex: {error}")
        if option == "--include":
            include_patterns.append(pattern)
        else:
            exclude_patterns.append(pattern)
        index += 2
    if not include_patterns:
        raise SystemExit("coverage selection requires at least one --include regex")
    source_fragment = None
    selection_label = "selected sources"

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
if source_fragment is not None:
    matching = [item for item in files if source_fragment in item.get("filename", "")]
else:
    matching = []
    for item in files:
        filename = item.get("filename", "")
        if any(pattern.search(filename) for pattern in include_patterns) and not any(
            pattern.search(filename) for pattern in exclude_patterns
        ):
            matching.append(item)
if not matching:
    if source_fragment is not None:
        raise SystemExit(f"coverage source path not found: {source_fragment}")
    raise SystemExit("coverage selection matched no source files")

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
        f"{selection_label} line coverage {percent:.2f}% is below required {threshold:.2f}% "
        f"({covered}/{executable})"
    )
print(
    f"{selection_label} line coverage {percent:.2f}% "
    f"({covered}/{executable} across {len(matching)} files)"
)
PY
