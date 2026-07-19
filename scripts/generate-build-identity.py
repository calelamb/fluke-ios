#!/usr/bin/python3 -I
"""Generate the provenance plist embedded in a signed Fluke archive."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile


VERSION = "1.1"
BUILD = "2"
MODEL_SOURCE_COMMIT = "6fe4767cd1c5716a04b655c9eaac4bd745471569"
MODEL_SOURCE_TREE = "fba0c558d30dd4b240e40c931b0ec8e5f4e9d29e"


class IdentityError(ValueError):
    """A safe, actionable build-identity failure."""


def git(checkout: Path, *arguments: str) -> str:
    result = subprocess.run(
        ["/usr/bin/git", "-C", str(checkout), *arguments],
        capture_output=True,
        check=False,
        text=True,
        env={"PATH": "/usr/bin:/bin", "LANG": "C", "LC_ALL": "C"},
    )
    if result.returncode != 0:
        raise IdentityError(f"git provenance check failed: {result.stderr.strip()}")
    return result.stdout.strip()


def sha256_file(path: Path) -> str:
    if path.is_symlink() or not path.is_file():
        raise IdentityError(f"required release file is missing or unsafe: {path}")
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def package_tree_sha256(package: Path) -> str:
    if package.is_symlink() or not package.is_dir():
        raise IdentityError("FlukeEmbedder.mlpackage is missing or unsafe")
    entries = tuple(
        sorted(
            package.rglob("*"), key=lambda item: item.relative_to(package).as_posix()
        )
    )
    if not entries:
        raise IdentityError("FlukeEmbedder.mlpackage must not be empty")
    digest = hashlib.sha256(b"fluke-coreml-package-v1\0")
    for path in entries:
        if path.is_symlink() or (not path.is_file() and not path.is_dir()):
            raise IdentityError("FlukeEmbedder.mlpackage contains an unsafe entry")
        relative = path.relative_to(package).as_posix().encode()
        digest.update(b"D" if path.is_dir() else b"F")
        digest.update(len(relative).to_bytes(8, "big"))
        digest.update(relative)
        if path.is_file():
            with path.open("rb") as source:
                for chunk in iter(lambda: source.read(1024 * 1024), b""):
                    digest.update(chunk)
    return digest.hexdigest()


def require_clean_checkout(checkout: Path, label: str) -> tuple[str, str]:
    if checkout.is_symlink() or not checkout.is_dir():
        raise IdentityError(f"{label} checkout is missing or unsafe")
    status = git(checkout, "status", "--porcelain", "--untracked-files=all")
    if status:
        raise IdentityError(f"{label} checkout is dirty")
    return git(checkout, "rev-parse", "HEAD"), git(checkout, "rev-parse", "HEAD^{tree}")


def require_output_under(output: Path, derived_data: Path) -> Path:
    root = derived_data.resolve(strict=True)
    candidate = output.resolve(strict=False)
    if os.path.commonpath((str(root), str(candidate))) != str(root):
        raise IdentityError("build identity output must be inside DerivedData")
    return candidate


def release_digests(release: Path, identifier_mode: str = "live") -> tuple[str, str]:
    report_path = release / "mobile-release-report.json"
    try:
        report = json.loads(report_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise IdentityError(
            f"mobile release report is missing or invalid: {error}"
        ) from error
    if not isinstance(report, dict):
        raise IdentityError("mobile release report must contain an object")
    if identifier_mode == "dormant":
        # A dormant archive bundles no catalog: matching stays off in the app,
        # so the report may be not-ready, but the model package stays pinned.
        model_digest = package_tree_sha256(release / "FlukeEmbedder.mlpackage")
        if report.get("modelPackageSha256") != model_digest:
            raise IdentityError("mobile release report model digest does not match")
        return model_digest, ""
    if report.get("ready") is not True:
        raise IdentityError("mobile release report must declare ready:true")
    catalog_digest = sha256_file(release / "catalog/manifest.json")
    for name in ("metadata.json", "references.f16"):
        sha256_file(release / f"catalog/{name}")
    model_digest = package_tree_sha256(release / "FlukeEmbedder.mlpackage")
    if report.get("modelPackageSha256") != model_digest:
        raise IdentityError("mobile release report model digest does not match")
    if report.get("catalogManifestSha256") != catalog_digest:
        raise IdentityError("mobile release report catalog digest does not match")
    return model_digest, catalog_digest


def generate(arguments: argparse.Namespace) -> dict[str, object]:
    if arguments.marketing_version != VERSION or arguments.build_number != BUILD:
        raise IdentityError(
            "Release identity requires marketing version 1.1 and build number 2"
        )
    output = require_output_under(arguments.output, arguments.derived_data)
    source_commit, source_tree = require_clean_checkout(arguments.repo, "iOS")
    model_commit, model_tree = require_clean_checkout(arguments.model_checkout, "model")
    if (model_commit, model_tree) != (MODEL_SOURCE_COMMIT, MODEL_SOURCE_TREE):
        raise IdentityError(
            "model checkout does not match the pinned reviewed revision"
        )
    model_digest, catalog_digest = release_digests(
        arguments.release, arguments.identifier_mode
    )
    return {
        "schemaVersion": 1,
        "sourceCommit": source_commit,
        "sourceTree": source_tree,
        "modelSourceCommit": model_commit,
        "modelSourceTree": model_tree,
        "marketingVersion": VERSION,
        "buildNumber": BUILD,
        "identifierMode": arguments.identifier_mode,
        "modelPackageSha256": model_digest,
        "catalogManifestSha256": catalog_digest,
        "output": output,
    }


def parse_arguments() -> argparse.Namespace:  # pragma: no cover - CLI glue
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True, type=Path)
    parser.add_argument("--model-checkout", required=True, type=Path)
    parser.add_argument("--release", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--derived-data", required=True, type=Path)
    parser.add_argument("--marketing-version", required=True)
    parser.add_argument("--build-number", required=True)
    parser.add_argument(
        "--identifier-mode", choices=("live", "dormant"), default="live"
    )
    return parser.parse_args()


def main() -> int:  # pragma: no cover - CLI glue
    try:
        identity = generate(parse_arguments())
        output = identity["output"]
        assert isinstance(output, Path)
        payload = {key: value for key, value in identity.items() if key != "output"}
        output.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(dir=output.parent, delete=False) as temporary:
            plistlib.dump(payload, temporary, sort_keys=True)
            temporary_path = Path(temporary.name)
        os.replace(temporary_path, output)
        print(f"Generated signed-app identity at {output}")
        return 0
    except (IdentityError, OSError) as error:
        print(f"Build identity error: {error}", file=__import__("sys").stderr)
        return 1


if __name__ == "__main__":  # pragma: no cover - CLI glue
    raise SystemExit(main())
