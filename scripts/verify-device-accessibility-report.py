#!/usr/bin/python3 -I
"""Fail closed unless an App Store report contains real passing iPhone evidence."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re


SHA = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")


class ReportError(ValueError):
    """An actionable evidence-contract failure."""


def require_number(value: object, label: str, *, minimum: float = 0) -> float:
    if (
        isinstance(value, bool)
        or not isinstance(value, (int, float))
        or value < minimum
    ):
        raise ReportError(f"{label} must be a measured number >= {minimum}")
    return float(value)


def validate(report: object) -> None:
    if not isinstance(report, dict) or report.get("schemaVersion") != 1:
        raise ReportError("device report schemaVersion must equal 1")
    if (
        report.get("status") != "complete"
        or report.get("physicalDeviceEvidenceComplete") is not True
    ):
        raise ReportError("physical iPhone evidence is incomplete")
    release = report.get("release")
    if release != {"marketingVersion": "1.1", "buildNumber": "2"}:
        raise ReportError("device report must bind version 1.1 build 2")
    provenance = report.get("provenance")
    if not isinstance(provenance, dict):
        raise ReportError("device report provenance is missing")
    for key in ("sourceCommit", "sourceTree", "modelSourceCommit", "modelSourceTree"):
        if not isinstance(provenance.get(key), str) or not SHA.fullmatch(
            provenance[key]
        ):
            raise ReportError(f"provenance {key} must be a full git SHA")
    if not isinstance(provenance.get("archiveSha256"), str) or not SHA256.fullmatch(
        provenance["archiveSha256"]
    ):
        raise ReportError("provenance archiveSha256 must be a SHA-256 digest")
    digests = provenance.get("evidenceDigests")
    if (
        not isinstance(digests, list)
        or not digests
        or any(
            not isinstance(item, str) or not SHA256.fullmatch(item) for item in digests
        )
    ):
        raise ReportError("provenance evidenceDigests must contain SHA-256 digests")
    device = report.get("device")
    if not isinstance(device, dict) or any(
        not isinstance(device.get(key), str) or not device[key].strip()
        for key in ("model", "iosVersion", "runAtUtc")
    ):
        raise ReportError("physical device identity and run time are required")
    performance = report.get("performance")
    if not isinstance(performance, dict):
        raise ReportError("performance evidence is missing")
    for temperature in ("cold", "warm"):
        latency = performance.get(f"{temperature}LatencyMs")
        if not isinstance(latency, dict):
            raise ReportError(f"{temperature} latency evidence is missing")
        p50 = require_number(latency.get("p50"), f"{temperature} p50 latency")
        p95 = require_number(latency.get("p95"), f"{temperature} p95 latency")
        if p50 > p95 or p95 > 500:
            raise ReportError(f"{temperature} latency requires p50 <= p95 <= 500 ms")
    for key in ("peakMemoryMB", "appSizeBytes", "binarySizeBytes"):
        require_number(performance.get(key), key, minimum=1)
    if require_number(performance.get("sustainedRunSeconds"), "sustained run") < 120:
        raise ReportError("sustained run must be at least 120 seconds")
    retained = require_number(performance.get("maxRetainedFrames"), "retained frames")
    if retained > 1:
        raise ReportError("at most one camera frame may be retained")
    runtime = report.get("runtime")
    required_runtime = (
        "thermalStateAcceptable",
        "previewContinuous",
        "backgroundSuspendsCamera",
        "airplaneModeIdentificationWorks",
        "airplaneModeSubmissionQueues",
    )
    if not isinstance(runtime, dict) or any(
        runtime.get(key) is not True for key in required_runtime
    ):
        raise ReportError(
            "thermal, preview, background, and airplane-mode cases must pass"
        )
    if runtime.get("identifierNetworkRequestCount") != 0:
        raise ReportError("identification must make zero network requests")
    accessibility = report.get("accessibility")
    required_accessibility = (
        "voiceOver",
        "dynamicTypeXXXL",
        "contrast",
        "reduceMotion",
        "cameraPermissionDenied",
        "photoPermissionDenied",
    )
    if not isinstance(accessibility, dict) or any(
        accessibility.get(key) is not True for key in required_accessibility
    ):
        raise ReportError("all accessibility and permission cases must pass")


def main() -> int:  # pragma: no cover - CLI glue
    parser = argparse.ArgumentParser()
    parser.add_argument("report", type=Path)
    arguments = parser.parse_args()
    try:
        validate(json.loads(arguments.report.read_text(encoding="utf-8")))
    except (OSError, UnicodeError, json.JSONDecodeError, ReportError) as error:
        print(f"Device evidence error: {error}", file=__import__("sys").stderr)
        return 1
    print("Physical-device and accessibility evidence is complete")
    return 0


if __name__ == "__main__":  # pragma: no cover - CLI glue
    raise SystemExit(main())
