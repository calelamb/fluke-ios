#!/usr/bin/python3 -I
"""Create or verify App Store screenshot provenance without inventing evidence."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re


EXPECTED_NAMES = (
    "01-sightings.png",
    "02-whales.png",
    "03-submit.png",
    "04-identify.png",
    "05-atlas.png",
    "06-you.png",
    "07-learn.png",
)
SHA = re.compile(r"^[0-9a-f]{40}$")


class ProvenanceError(ValueError):
    """A screenshot provenance failure safe to show to a release operator."""


def load_identity_module(repo: Path):
    path = repo / "scripts/generate-build-identity.py"
    spec = importlib.util.spec_from_file_location("fluke_build_identity", path)
    if spec is None or spec.loader is None:
        raise ProvenanceError("build identity generator is unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def sha256(path: Path) -> str:
    if path.is_symlink() or not path.is_file():
        raise ProvenanceError(f"screenshot input is missing or unsafe: {path}")
    return hashlib.sha256(path.read_bytes()).hexdigest()


def screenshot_digests(directory: Path) -> dict[str, str]:
    names = tuple(sorted(path.name for path in directory.glob("*.png")))
    if names != EXPECTED_NAMES:
        raise ProvenanceError(
            "screenshot set must contain the exact seven canonical PNG names"
        )
    return {name: sha256(directory / name) for name in EXPECTED_NAMES}


def old_release_digests(repo: Path) -> set[str]:
    return {
        sha256(path)
        for path in (repo / "AppStore/1.0/en-US/screenshots").rglob("*.png")
        if path.is_file() and not path.is_symlink()
    }


def create(arguments: argparse.Namespace) -> dict[str, object]:
    identity = load_identity_module(arguments.repo)
    if not SHA.fullmatch(arguments.source_commit) or not SHA.fullmatch(
        arguments.source_tree
    ):
        raise ProvenanceError("source commit and tree must be full git SHAs")
    if (
        identity.git(arguments.repo, "rev-parse", f"{arguments.source_commit}^{{tree}}")
        != arguments.source_tree
    ):
        raise ProvenanceError("source commit does not resolve to the recorded tree")
    model_commit, model_tree = identity.require_clean_checkout(
        arguments.model_checkout, "model"
    )
    if (model_commit, model_tree) != (
        identity.MODEL_SOURCE_COMMIT,
        identity.MODEL_SOURCE_TREE,
    ):
        raise ProvenanceError(
            "model checkout does not match the pinned reviewed revision"
        )
    model_digest, catalog_digest = identity.release_digests(arguments.release)
    digests = screenshot_digests(arguments.screenshots)
    if set(digests.values()) & old_release_digests(arguments.repo):
        raise ProvenanceError(
            "App Store 1.1 screenshots must not reuse version 1.0 images"
        )
    return {
        "schemaVersion": 1,
        "sourceCommit": arguments.source_commit,
        "sourceTree": arguments.source_tree,
        "marketingVersion": "1.1",
        "buildNumber": "2",
        "runtime": arguments.runtime,
        "device": arguments.device,
        "locale": "en-US",
        "modelSourceCommit": model_commit,
        "modelSourceTree": model_tree,
        "modelPackageSha256": model_digest,
        "catalogManifestSha256": catalog_digest,
        "fixtureSource": {
            "path": "App/Fluke/AppStoreScreenshotFixtures.swift",
            "sha256": sha256(
                arguments.repo / "App/Fluke/AppStoreScreenshotFixtures.swift"
            ),
            "identificationEnabled": False,
        },
        "screenshots": digests,
    }


def verify(arguments: argparse.Namespace) -> None:
    try:
        observed = json.loads(arguments.manifest.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ProvenanceError(
            f"screenshot provenance manifest is invalid: {error}"
        ) from error
    expected = create(arguments)
    if observed != expected:
        differing = next(
            (key for key in expected if observed.get(key) != expected[key]), "fields"
        )
        raise ProvenanceError(f"screenshot provenance mismatch: {differing}")


def parse_arguments() -> argparse.Namespace:  # pragma: no cover - CLI glue
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("create", "verify"))
    parser.add_argument("--repo", required=True, type=Path)
    parser.add_argument("--screenshots", required=True, type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--model-checkout", required=True, type=Path)
    parser.add_argument("--release", required=True, type=Path)
    parser.add_argument("--source-commit", required=True)
    parser.add_argument("--source-tree", required=True)
    parser.add_argument("--runtime", required=True)
    parser.add_argument("--device", required=True)
    return parser.parse_args()


def main() -> int:  # pragma: no cover - CLI glue
    arguments = parse_arguments()
    try:
        if arguments.mode == "create":
            payload = create(arguments)
            arguments.manifest.write_text(
                json.dumps(payload, indent=2, sort_keys=True) + "\n"
            )
            print(f"Wrote screenshot provenance to {arguments.manifest}")
        else:
            verify(arguments)
            print("Screenshot provenance is valid")
        return 0
    except (OSError, ProvenanceError, ValueError) as error:
        print(f"Screenshot provenance error: {error}", file=__import__("sys").stderr)
        return 1


if __name__ == "__main__":  # pragma: no cover - CLI glue
    raise SystemExit(main())
