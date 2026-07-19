#!/usr/bin/python3 -I
"""Verify the archived runtime dependency allowlist and transport denylist."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import plistlib


TELEMETRY_MARKERS = (
    b"firebaseanalytics",
    b"sentrysdk",
    b"datadog",
    b"mixpanel",
    b"amplitude",
    b"segmentanalytics",
    b"appcenter",
    b"telemetrydeck",
)
IDENTIFIER_TRANSPORT_MARKERS = (
    b"/api/v1/identify",
    b"/identification/upload",
    b"/identifier/upload",
    b"identifiertelemetry",
    b"matchembeddingupload",
)


class RuntimeError(ValueError):
    """An archive-runtime verification failure."""


def archive_app(archive: Path) -> Path:
    try:
        with (archive / "Info.plist").open("rb") as source:
            info = plistlib.load(source)
    except (OSError, plistlib.InvalidFileException) as error:
        raise RuntimeError(f"archive Info.plist is invalid: {error}") from error
    relative = info.get("ApplicationProperties", {}).get("ApplicationPath")
    if relative != "Applications/Fluke.app":
        raise RuntimeError("archive must contain Applications/Fluke.app")
    app = archive / "Products/Applications/Fluke.app"
    if app.is_symlink() or not app.is_dir():
        raise RuntimeError("archived Fluke.app is missing or unsafe")
    return app


def validate(archive: Path, allowlist_path: Path) -> str:
    try:
        allowlist_bytes = allowlist_path.read_bytes()
        allowlist = json.loads(allowlist_bytes)
    except (OSError, json.JSONDecodeError) as error:
        raise RuntimeError(f"runtime allowlist is invalid: {error}") from error
    expected_keys = {
        "schemaVersion",
        "purpose",
        "frameworks",
        "telemetryFrameworks",
        "identifierTransportArtifacts",
    }
    if (
        not isinstance(allowlist, dict)
        or set(allowlist) != expected_keys
        or allowlist["schemaVersion"] != 1
    ):
        raise RuntimeError("runtime allowlist fields do not match schemaVersion 1")
    if (
        allowlist["telemetryFrameworks"] != []
        or allowlist["identifierTransportArtifacts"] != []
    ):
        raise RuntimeError(
            "telemetry and identifier transport allowlists must remain empty"
        )
    app = archive_app(archive)
    frameworks_root = app / "Frameworks"
    observed_frameworks = (
        tuple(sorted(path.name for path in frameworks_root.iterdir()))
        if frameworks_root.is_dir()
        else ()
    )
    if observed_frameworks != tuple(allowlist["frameworks"]):
        raise RuntimeError(
            f"embedded frameworks differ from runtime allowlist: {observed_frameworks}"
        )
    for path in app.rglob("*"):
        if path.is_symlink() or (not path.is_file() and not path.is_dir()):
            raise RuntimeError("archive contains an unsafe runtime entry")
        if not path.is_file() or path.stat().st_size > 128 * 1024 * 1024:
            continue
        lowered_name = path.name.lower().encode()
        if any(
            marker in lowered_name
            for marker in TELEMETRY_MARKERS + IDENTIFIER_TRANSPORT_MARKERS
        ):
            raise RuntimeError(f"forbidden runtime artifact name: {path.name}")
        data = path.read_bytes().lower()
        if any(marker in data for marker in TELEMETRY_MARKERS):
            raise RuntimeError(f"telemetry marker found in archive: {path.name}")
        if any(marker in data for marker in IDENTIFIER_TRANSPORT_MARKERS):
            raise RuntimeError(
                f"identifier transport marker found in archive: {path.name}"
            )
    return hashlib.sha256(allowlist_bytes).hexdigest()


def main() -> int:  # pragma: no cover - CLI glue
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=Path)
    parser.add_argument("allowlist", type=Path)
    arguments = parser.parse_args()
    try:
        digest = validate(arguments.archive, arguments.allowlist)
    except (OSError, RuntimeError, ValueError) as error:
        print(f"Archive runtime error: {error}", file=__import__("sys").stderr)
        return 1
    print(f"Archive runtime allowlist is valid (sha256:{digest})")
    return 0


if __name__ == "__main__":  # pragma: no cover - CLI glue
    raise SystemExit(main())
