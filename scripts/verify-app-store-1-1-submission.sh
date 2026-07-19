#!/usr/bin/env python3
"""Fail-closed App Store 1.1 verification bound to source, evidence, and archive."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from typing import Callable

MODEL_SOURCE_COMMIT = "6fe4767cd1c5716a04b655c9eaac4bd745471569"
MODEL_SOURCE_TREE = "fba0c558d30dd4b240e40c931b0ec8e5f4e9d29e"
MODEL_VERIFIER_SHA256 = "188e88512d500b932794dc56e45f8e7a305cc22fd9da2a482890e211b4568924"
MODEL_UV_LOCK_SHA256 = "f9be2cbfe4efcb499f074b660ca6ef3ce04c5ac1a56b8233456cd39bfc7260e7"
MODEL_PYPROJECT_SHA256 = "70fb5c14ecd6a67f43d3023d82b6cfbd3408c5d94415a1ba0681f8ceeefce098"
UV_EXECUTABLE_SHA256 = "51f0ae3c531a124727fa39e16e8599f2e371e427822a4aa92ebf667b52548b43"
VERSION = "1.1"
BUILD = "2"
BUNDLE_ID = "app.fluke.Fluke"
REPORT_NAME = "mobile-release-report.json"
SCREENSHOT_SIZES = {(1260, 2736), (2736, 1260), (1290, 2796), (2796, 1290), (1320, 2868), (2868, 1320)}
MAX_STRUCTURED_FILE_BYTES = 16 * 1024 * 1024
MAX_SCREENSHOT_BYTES = 50 * 1024 * 1024


class VerificationError(ValueError):
    """A bounded, user-facing release verification failure."""


class _ArgumentParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        raise VerificationError(f"usage: MODEL_CHECKOUT RELEASE_DIRECTORY ARCHIVE ({message})")


def parse_arguments(arguments: list[str] | None = None) -> argparse.Namespace:
    parser = _ArgumentParser(
        description="Verify App Store 1.1 against a reviewed model checkout and real archive"
    )
    parser.add_argument("model_checkout", type=Path)
    parser.add_argument("release_directory", type=Path)
    parser.add_argument("archive", type=Path)
    return parser.parse_args(arguments)


def sanitized_environment() -> dict[str, str]:
    """Return the small fixed environment used for all release subprocesses."""
    return {
        "HOME": str(Path.home()),
        "PATH": "/usr/bin:/bin",
        "LANG": "C.UTF-8",
        "LC_ALL": "C.UTF-8",
        "PYTHONNOUSERSITE": "1",
        "UV_NO_CONFIG": "1",
        "UV_OFFLINE": "1",
    }


def _reject_symlink_components(path: Path, label: str) -> None:
    absolute = path.absolute()
    platform_aliases = {Path("/tmp"), Path("/var")}
    for component in (*reversed(absolute.parents), absolute):
        try:
            if component not in platform_aliases and component.is_symlink():
                raise VerificationError(f"{label} path contains a symbolic link")
        except OSError as error:
            raise VerificationError(f"cannot inspect {label}: {error}") from error


def _require_regular(path: Path, label: str) -> None:
    _reject_symlink_components(path, label)
    try:
        mode = path.stat(follow_symlinks=False).st_mode
    except OSError as error:
        raise VerificationError(f"{label} is missing: {error}") from error
    if not stat.S_ISREG(mode):
        raise VerificationError(f"{label} must be a regular file")


def read_bytes_no_follow(path: Path, label: str) -> bytes:
    _require_regular(path, label)
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(path, flags)
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode):
            raise VerificationError(f"{label} must be a regular file")
        if metadata.st_size > MAX_STRUCTURED_FILE_BYTES:
            raise VerificationError(f"{label} exceeds the bounded structured-file size")
        with os.fdopen(descriptor, "rb", closefd=False) as source:
            return source.read()
    except OSError as error:
        raise VerificationError(f"cannot read {label}: {error}") from error
    finally:
        os.close(descriptor)


def read_json_no_follow(path: Path, label: str) -> object:
    try:
        return json.loads(read_bytes_no_follow(path, label).decode("utf-8"))
    except (UnicodeError, json.JSONDecodeError) as error:
        raise VerificationError(f"invalid {label}: {error}") from error


def read_plist_no_follow(path: Path, label: str) -> dict[str, object]:
    try:
        value = plistlib.loads(read_bytes_no_follow(path, label))
    except plistlib.InvalidFileException as error:
        raise VerificationError(f"invalid {label}: {error}") from error
    if not isinstance(value, dict):
        raise VerificationError(f"invalid {label}: expected a dictionary")
    return value


def _sha256_file(path: Path, label: str) -> str:
    _require_regular(path, label)
    digest = hashlib.sha256()
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(path, flags)
    try:
        with os.fdopen(descriptor, "rb", closefd=False) as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
    finally:
        os.close(descriptor)
    return digest.hexdigest()


def _package_tree_sha256(package: Path, label: str) -> str:
    _reject_symlink_components(package, label)
    if not package.is_dir():
        raise VerificationError(f"{label} must be a regular directory")
    entries = tuple(sorted(package.rglob("*"), key=lambda path: path.relative_to(package).as_posix()))
    if not entries:
        raise VerificationError(f"{label} must not be empty")
    digest = hashlib.sha256(b"fluke-coreml-package-v1\0")
    for path in entries:
        _reject_symlink_components(path, label)
        relative = path.relative_to(package).as_posix().encode("utf-8")
        if path.is_dir():
            digest.update(b"D")
        elif path.is_file():
            digest.update(b"F")
        else:
            raise VerificationError(f"{label} contains a non-regular entry")
        digest.update(len(relative).to_bytes(8, "big"))
        digest.update(relative)
        if path.is_file():
            flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
            descriptor = os.open(path, flags)
            try:
                with os.fdopen(descriptor, "rb", closefd=False) as source:
                    for chunk in iter(lambda: source.read(1024 * 1024), b""):
                        digest.update(chunk)
            finally:
                os.close(descriptor)
    return digest.hexdigest()


def screenshot_digest_denylist(app_store_1_0: Path) -> set[str]:
    screenshot_root = app_store_1_0 / "en-US/screenshots"
    if not screenshot_root.exists():
        return set()
    return {
        _sha256_file(path, "App Store 1.0 screenshot")
        for path in screenshot_root.rglob("*")
        if path.is_file() and path.suffix.lower() in {".png", ".jpg", ".jpeg"}
    }


def validate_screenshot_path(path: Path, denylist: set[str]) -> None:
    _require_regular(path, "App Store 1.1 screenshot")
    if path.stat(follow_symlinks=False).st_size > MAX_SCREENSHOT_BYTES:
        raise VerificationError(f"App Store 1.1 screenshot exceeds the bounded size: {path.name}")
    digest = _sha256_file(path, "App Store 1.1 screenshot")
    if digest in denylist:
        raise VerificationError(f"App Store 1.1 screenshot reuses a 1.0 screenshot: {path.name}")


def _validate_screenshot_geometry(path: Path) -> None:
    command = ["/usr/bin/sips", "-g", "pixelWidth", "-g", "pixelHeight", "-g", "hasAlpha", str(path)]
    result = subprocess.run(command, capture_output=True, text=True, env=sanitized_environment(), check=False)
    if result.returncode != 0:
        raise VerificationError(f"cannot inspect screenshot {path.name}: {result.stderr.strip()}")
    width = re.search(r"pixelWidth:\s*(\d+)", result.stdout)
    height = re.search(r"pixelHeight:\s*(\d+)", result.stdout)
    alpha = re.search(r"hasAlpha:\s*(\w+)", result.stdout)
    if not width or not height or (int(width.group(1)), int(height.group(1))) not in SCREENSHOT_SIZES:
        raise VerificationError(f"screenshot is not an accepted 6.9-inch size: {path.name}")
    if not alpha or alpha.group(1) != "no":
        raise VerificationError(f"screenshot must be opaque: {path.name}")


def _type_matches(value: object, expected: str) -> bool:
    return {
        "array": isinstance(value, list), "boolean": isinstance(value, bool),
        "integer": isinstance(value, int) and not isinstance(value, bool),
        "null": value is None, "object": isinstance(value, dict), "string": isinstance(value, str),
    }.get(expected, False)


def _validate_schema(value: object, schema: dict[str, object], path: str = "$") -> None:
    if "const" in schema and value != schema["const"]:
        raise VerificationError(f"{path} must equal {schema['const']}")
    if "enum" in schema and value not in schema["enum"]:
        raise VerificationError(f"{path} is not an allowed value")
    expected_type = schema.get("type")
    if isinstance(expected_type, str) and not _type_matches(value, expected_type):
        raise VerificationError(f"{path} must be {expected_type}")
    if isinstance(value, dict):
        properties = schema.get("properties", {})
        if not isinstance(properties, dict):
            raise VerificationError(f"invalid schema properties at {path}")
        for key in schema.get("required", []):
            if key not in value:
                raise VerificationError(f"{path}.{key} is required")
        if schema.get("additionalProperties") is False:
            extras = sorted(set(value) - set(properties))
            if extras:
                raise VerificationError(f"{path} has unsupported fields: {', '.join(extras)}")
        for key, child in value.items():
            if key in properties:
                _validate_schema(child, properties[key], f"{path}.{key}")
    elif isinstance(value, list):
        if len(value) < schema.get("minItems", 0) or len(value) > schema.get("maxItems", len(value)):
            raise VerificationError(f"{path} has an invalid item count")
        item_schema = schema.get("items")
        if isinstance(item_schema, dict):
            for index, child in enumerate(value):
                _validate_schema(child, item_schema, f"{path}[{index}]")
    elif isinstance(value, str) and len(value) > schema.get("maxLength", len(value)):
        raise VerificationError(f"{path} exceeds {schema['maxLength']} characters")


def validate_package(repo_root: Path) -> None:
    package = repo_root / "AppStore/1.1"
    pairs = (
        ("en-US/metadata.json", "schemas/metadata.schema.json"),
        ("app-privacy.json", "schemas/app-privacy.schema.json"),
        ("review-submission.json", "schemas/review-submission.schema.json"),
    )
    loaded: dict[str, object] = {}
    for document_name, schema_name in pairs:
        document = read_json_no_follow(package / document_name, document_name)
        schema = read_json_no_follow(package / schema_name, schema_name)
        if not isinstance(schema, dict):
            raise VerificationError(f"{schema_name} must contain an object")
        _validate_schema(document, schema)
        loaded[document_name] = document
    metadata = loaded["en-US/metadata.json"]
    if not isinstance(metadata, dict):
        raise VerificationError("metadata must contain an object")
    copy = " ".join(str(metadata[key]) for key in ("description", "promotionalText", "whatsNew", "reviewNotes")).lower()
    required_copy = (
        "camera frames", "stay on device", "no analytics or tracking", "explicit sighting submission",
        "optional account", "account email", "identity token", "authorization code", "dorsal fin",
        "orca individual", "without capture or upload", "ready:true",
    )
    missing = next((text for text in required_copy if text not in copy), None)
    if missing:
        raise VerificationError(f"metadata is missing required truthful copy: {missing}")
    if any(text in copy for text in ("fluke matching", "fluke photo", "at a fluke")):
        raise VerificationError("metadata contains misleading fluke-identification copy")
    expected_urls = {
        "supportURL": "https://fluke-pnw.vercel.app/support",
        "privacyURL": "https://fluke-pnw.vercel.app/privacy",
        "marketingURL": "https://fluke-pnw.vercel.app",
    }
    if any(metadata.get(key) != value for key, value in expected_urls.items()):
        raise VerificationError("metadata live URLs do not match the shipping contract")
    if len(str(metadata.get("keywords", "")).encode("utf-8")) > 100:
        raise VerificationError("metadata keywords exceed 100 UTF-8 bytes")
    privacy = loaded["app-privacy.json"]
    if not isinstance(privacy, dict):
        raise VerificationError("app privacy declaration must contain an object")
    manifest = read_plist_no_follow(repo_root / "App/Fluke/PrivacyInfo.xcprivacy", "shipping privacy manifest")
    apple_to_draft = {
        "NSPrivacyCollectedDataTypeEmailAddress": "email-address",
        "NSPrivacyCollectedDataTypeName": "name",
        "NSPrivacyCollectedDataTypePhotosorVideos": "photos-or-videos",
        "NSPrivacyCollectedDataTypeCoarseLocation": "coarse-location",
        "NSPrivacyCollectedDataTypeUserID": "user-id",
        "NSPrivacyCollectedDataTypeOtherUserContent": "other-user-content",
    }
    manifest_entries = manifest.get("NSPrivacyCollectedDataTypes")
    declared_entries = privacy.get("collectedData")
    if not isinstance(manifest_entries, list) or not isinstance(declared_entries, list):
        raise VerificationError("shipping privacy categories are missing")
    manifest_types = [apple_to_draft.get(entry.get("NSPrivacyCollectedDataType")) for entry in manifest_entries if isinstance(entry, dict)]
    declared_types = [entry.get("dataType") for entry in declared_entries if isinstance(entry, dict)]
    if manifest_types != declared_types or len(manifest_types) != len(manifest_entries):
        raise VerificationError("App Store privacy categories do not match the shipping manifest")
    receipt = loaded["review-submission.json"]
    if not isinstance(receipt, dict) or receipt.get("status") != "draft" or receipt.get("submitted") is not False:
        raise VerificationError("review submission must remain an unsubmitted draft")
    screenshots = sorted(
        path for path in (package / "en-US/screenshots/6.9-inch").glob("*")
        if path.suffix.lower() in {".png", ".jpg", ".jpeg"}
    )
    if not 1 <= len(screenshots) <= 10:
        raise VerificationError("App Store 1.1 requires 1-10 accepted opaque 6.9-inch screenshots; none are fabricated by this package")
    denylist = screenshot_digest_denylist(repo_root / "AppStore/1.0")
    for screenshot in screenshots:
        validate_screenshot_path(screenshot, denylist)
        _validate_screenshot_geometry(screenshot)


def _run_git(checkout: Path, arguments: list[str]) -> str:
    result = subprocess.run(
        ["/usr/bin/git", "-C", str(checkout), *arguments], capture_output=True, text=True,
        env=sanitized_environment(), check=False,
    )
    if result.returncode != 0:
        raise VerificationError(f"git provenance check failed: {result.stderr.strip()}")
    return result.stdout.strip()


def validate_model_checkout_and_release(checkout: Path, release: Path) -> None:
    _reject_symlink_components(checkout, "fluke-model checkout")
    _reject_symlink_components(release, "mobile release directory")
    if not checkout.is_dir() or not release.is_dir():
        raise VerificationError("model checkout and release directory must be regular directories")
    if _run_git(checkout, ["rev-parse", "HEAD"]) != MODEL_SOURCE_COMMIT:
        raise VerificationError("fluke-model checkout is not at the reviewed source commit")
    if _run_git(checkout, ["rev-parse", "HEAD^{tree}"]) != MODEL_SOURCE_TREE:
        raise VerificationError("fluke-model checkout tree does not match the reviewed tree")
    relevant = ["scripts/verify_mobile_release.py", "src", "uv.lock", "pyproject.toml"]
    status = _run_git(checkout, ["status", "--porcelain", "--untracked-files=all", "--", *relevant])
    if status:
        raise VerificationError("fluke-model checkout has dirty or untracked verifier inputs")
    pinned_files = {
        "scripts/verify_mobile_release.py": MODEL_VERIFIER_SHA256,
        "uv.lock": MODEL_UV_LOCK_SHA256,
        "pyproject.toml": MODEL_PYPROJECT_SHA256,
    }
    for relative, digest in pinned_files.items():
        if _sha256_file(checkout / relative, f"fluke-model {relative}") != digest:
            raise VerificationError(f"fluke-model {relative} does not match reviewed provenance")


def _find_uv() -> Path:
    discovered = shutil.which("uv")
    if discovered is None:
        raise VerificationError("the pinned uv executable is unavailable")
    candidate = Path(discovered).absolute()
    if candidate.is_symlink() or not candidate.is_file() or not os.access(candidate, os.X_OK):
        raise VerificationError("uv must resolve to a regular executable")
    if _sha256_file(candidate, "uv executable") != UV_EXECUTABLE_SHA256:
        raise VerificationError("uv executable does not match the pinned release-tool identity")
    return candidate


def run_mobile_release_verifier(checkout: Path, release: Path) -> None:
    report = release / REPORT_NAME
    _reject_symlink_components(report, "mobile release report")
    command = [
        str(_find_uv()), "run", "--offline", "--locked", "--project", str(checkout), "python",
        str(checkout / "scripts/verify_mobile_release.py"), "--release-dir", str(release),
        "--report", str(report),
    ]
    result = subprocess.run(command, capture_output=True, text=True, env=sanitized_environment(), check=False)
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise VerificationError(f"fresh mobile release verification failed: {detail}")
    if not report.is_file() or report.is_symlink():
        raise VerificationError("fresh mobile release verifier did not produce a regular report")


def validate_release_report(release: Path) -> dict[str, str]:
    report = read_json_no_follow(release / REPORT_NAME, "fresh mobile release report")
    if not isinstance(report, dict) or set(report) != {
        "schemaVersion", "modelPackageSha256", "catalogManifestSha256", "ready", "thresholds", "gates"
    }:
        raise VerificationError("fresh mobile release report fields do not match the exact schema")
    if report.get("schemaVersion") != 1 or report.get("ready") is not True:
        raise VerificationError("fresh mobile release report is not ready")
    if report.get("thresholds") != {"false_accept": 0.05, "parity_cosine": 0.999, "top_1": 0.65, "top_3": 0.8}:
        raise VerificationError("fresh mobile release thresholds do not match")
    expected_names = (
        "model_package_digest", "catalog_manifest_digest", "input_paths", "package", "catalog",
        "digests", "rights", "embedding_shape", "embedding_norm", "required_reports",
        "parity_samples", "parity_cosine", "closed_set_samples", "top_1", "top_3",
        "open_set_samples", "false_accept",
    )
    gates = report.get("gates")
    if not isinstance(gates, list) or tuple(gate.get("name") for gate in gates if isinstance(gate, dict)) != expected_names:
        raise VerificationError("fresh mobile release gate order does not match")
    for gate in gates:
        if not isinstance(gate, dict) or set(gate) != {"name", "passed", "observed", "requirement", "detail"} or gate["passed"] is not True:
            raise VerificationError("fresh mobile release gate evidence is invalid")
    model_digest = _package_tree_sha256(release / "FlukeEmbedder.mlpackage", "verified model package")
    catalog_digest = _sha256_file(release / "catalog/manifest.json", "verified catalog manifest")
    if report.get("modelPackageSha256") != model_digest or report.get("catalogManifestSha256") != catalog_digest:
        raise VerificationError("fresh mobile release report does not bind the release artifacts")
    gate_map = {gate["name"]: gate for gate in gates}
    if gate_map["model_package_digest"]["observed"] != model_digest or gate_map["catalog_manifest_digest"]["observed"] != catalog_digest:
        raise VerificationError("fresh mobile release digest gates do not bind report identity")
    return {"model": model_digest, "catalog": catalog_digest}


def _object_block(project: str, identifier: str, comment: str) -> str:
    match = re.search(rf"(?ms)^\s*{re.escape(identifier)} /\* {re.escape(comment)} \*/ = \{{(.*?)^\s*\}};", project)
    if not match:
        raise VerificationError(f"project object is missing: {comment}")
    return match.group(1)


def validate_project(project_path: Path) -> None:
    project = read_bytes_no_follow(project_path, "Xcode project").decode("utf-8")
    list_match = re.search(r"([A-F0-9]+) /\* Build configuration list for PBXNativeTarget \"Fluke\" \*/ = \{", project)
    target_match = re.search(r"(?ms)^\s*([A-F0-9]+) /\* Fluke \*/ = \{\s*isa = PBXNativeTarget;(.*?)^\s*\};", project)
    if not list_match or not target_match or list_match.group(1) not in target_match.group(2):
        raise VerificationError("cannot identify the shipping Fluke target configuration list")
    list_block = _object_block(project, list_match.group(1), 'Build configuration list for PBXNativeTarget "Fluke"')
    release_match = re.search(r"([A-F0-9]+) /\* Release \*/", list_block)
    if not release_match:
        raise VerificationError("shipping Fluke target has no Release configuration")
    release_block = _object_block(project, release_match.group(1), "Release")
    for key, expected in (("MARKETING_VERSION", VERSION), ("CURRENT_PROJECT_VERSION", BUILD), ("PRODUCT_BUNDLE_IDENTIFIER", BUNDLE_ID)):
        match = re.search(rf"\b{key}\s*=\s*([^;]+);", release_block)
        if not match or match.group(1).strip().strip('"') != expected:
            raise VerificationError(f"shipping Fluke Release {key} must equal {expected}")
    exception_blocks = re.findall(
        r"(?ms)isa = PBXFileSystemSynchronizedBuildFileExceptionSet;(.*?target = ([A-F0-9]+) /\* Fluke \*/;.*?)^\s*\};",
        project,
    )
    protected = ("Models/FlukeEmbedder", "IdentifierCatalog", "manifest.json", "metadata.json", "references.f16")
    if any(target == target_match.group(1) and any(value in block for value in protected) for block, target in exception_blocks):
        raise VerificationError("shipping identification resource appears in a Fluke membership exception")
    if "PBXFileSystemSynchronizedRootGroup" not in project or "/* Resources */" not in target_match.group(2):
        raise VerificationError("Fluke synchronized resource membership is not established")


def validate_xcode_build_settings(repo_root: Path) -> None:
    command = [
        "/usr/bin/xcodebuild", "-project", str(repo_root / "App/Fluke.xcodeproj"), "-scheme", "Fluke",
        "-configuration", "Release", "-showBuildSettings",
    ]
    result = subprocess.run(command, capture_output=True, text=True, env=sanitized_environment(), check=False)
    if result.returncode != 0:
        raise VerificationError(f"xcodebuild Release settings failed: {result.stderr.strip()}")
    values: dict[str, str] = {}
    for line in result.stdout.splitlines():
        match = re.match(r"\s*(TARGET_NAME|PRODUCT_BUNDLE_IDENTIFIER|MARKETING_VERSION|CURRENT_PROJECT_VERSION)\s*=\s*(.*?)\s*$", line)
        if match:
            values[match.group(1)] = match.group(2)
    expected = {"TARGET_NAME": "Fluke", "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID, "MARKETING_VERSION": VERSION, "CURRENT_PROJECT_VERSION": BUILD}
    if values != expected:
        raise VerificationError(f"sanitized xcodebuild settings do not match shipping contract: {values}")


def _archive_app(archive: Path) -> tuple[Path, dict[str, object], dict[str, object]]:
    _reject_symlink_components(archive, "App Store archive")
    if not archive.is_dir():
        raise VerificationError("App Store archive must be a regular directory")
    archive_info = read_plist_no_follow(archive / "Info.plist", "archive Info.plist")
    properties = archive_info.get("ApplicationProperties")
    if not isinstance(properties, dict) or properties.get("ApplicationPath") != "Applications/Fluke.app":
        raise VerificationError("archive application path must be Applications/Fluke.app")
    app = archive / "Products/Applications/Fluke.app"
    _reject_symlink_components(app, "archived Fluke app")
    if not app.is_dir():
        raise VerificationError("archived Fluke app is missing")
    app_info = read_plist_no_follow(app / "Info.plist", "archived app Info.plist")
    expected = {"CFBundleIdentifier": BUNDLE_ID, "CFBundleShortVersionString": VERSION, "CFBundleVersion": BUILD}
    for key, value in expected.items():
        if properties.get(key) != value or app_info.get(key) != value:
            raise VerificationError(f"archive and app {key} must equal {value}")
    return app, archive_info, app_info


def validate_archive(
    archive: Path,
    release: Path,
    digests: dict[str, str],
    source_commit: str,
    source_tree: str,
    *,
    compiled_model_validator: Callable[[Path], None],
) -> None:
    _reject_symlink_components(archive, "App Store archive")
    for entry in archive.rglob("*"):
        _reject_symlink_components(entry, "App Store archive")
        if not entry.is_dir() and not entry.is_file():
            raise VerificationError("App Store archive contains a non-regular entry")
    app, _, _ = _archive_app(archive)
    for filename in ("manifest.json", "metadata.json", "references.f16"):
        released = release / "catalog" / filename
        archived = app / "IdentifierCatalog" / filename
        if _sha256_file(released, f"release catalog {filename}") != _sha256_file(archived, f"archived catalog {filename}"):
            raise VerificationError(f"archived IdentifierCatalog does not match release: {filename}")
    model_candidates = (app / "FlukeEmbedder.mlmodelc", app / "Models/FlukeEmbedder.mlmodelc")
    compiled = [path for path in model_candidates if path.exists() or path.is_symlink()]
    if len(compiled) != 1:
        raise VerificationError("archive must contain exactly one compiled FlukeEmbedder.mlmodelc")
    _reject_symlink_components(compiled[0], "compiled FlukeEmbedder.mlmodelc")
    if not compiled[0].is_dir():
        raise VerificationError("compiled FlukeEmbedder.mlmodelc must be a regular directory")
    for entry in compiled[0].rglob("*"):
        _reject_symlink_components(entry, "compiled FlukeEmbedder.mlmodelc")
    identity = read_plist_no_follow(archive / "FlukeBuildIdentity.plist", "archive build identity")
    expected_identity = {
        "schemaVersion": 1,
        "sourceCommit": source_commit,
        "sourceTree": source_tree,
        "modelSourceCommit": MODEL_SOURCE_COMMIT,
        "modelSourceTree": MODEL_SOURCE_TREE,
        "marketingVersion": VERSION,
        "buildNumber": BUILD,
        "modelPackageSha256": digests["model"],
        "catalogManifestSha256": digests["catalog"],
    }
    if identity != expected_identity:
        mismatch = next((key for key in expected_identity if identity.get(key) != expected_identity[key]), "fields")
        raise VerificationError(f"archive build identity mismatch: {mismatch}")
    compiled_model_validator(compiled[0])


def validate_compiled_model(model: Path) -> None:
    swift = r'''
import CoreML
import Foundation
do {
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let configuration = MLModelConfiguration()
let model = try MLModel(contentsOf: url, configuration: configuration)
let description = model.modelDescription
guard Set(description.inputDescriptionsByName.keys) == ["pixels"],
      Set(description.outputDescriptionsByName.keys) == ["embedding"],
      let input = description.inputDescriptionsByName["pixels"]?.multiArrayConstraint,
      input.dataType == .float32, input.shape.map({ $0.intValue }) == [1, 3, 224, 224],
      let output = description.outputDescriptionsByName["embedding"]?.multiArrayConstraint,
      output.dataType == .float32, output.shape.map({ $0.intValue }) == [1, 384]
else { throw NSError(domain: "FlukeModelContract", code: 1) }
let pixels = try MLMultiArray(shape: [1, 3, 224, 224], dataType: .float32)
let prediction = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["pixels": pixels]))
guard prediction.featureNames == ["embedding"],
      let embedding = prediction.featureValue(for: "embedding")?.multiArrayValue,
      embedding.dataType == .float32, embedding.shape.map({ $0.intValue }) == [1, 384]
else { throw NSError(domain: "FlukeModelPrediction", code: 2) }
let values = (0..<embedding.count).map { embedding[$0].doubleValue }
let norm = sqrt(values.reduce(0) { $0 + $1 * $1 })
guard values.allSatisfy({ $0.isFinite }), norm.isFinite, abs(norm - 1) <= 0.001
else { throw NSError(domain: "FlukeModelPrediction", code: 3) }
} catch {
  fputs("compiled model validation failed\n", stderr)
  exit(1)
}
'''
    with tempfile.TemporaryDirectory(prefix="fluke-model-archive-check.") as temporary:
        script = Path(temporary) / "validate.swift"
        script.write_text(swift, encoding="utf-8")
        result = subprocess.run(
            ["/usr/bin/xcrun", "swift", str(script), str(model)], capture_output=True, text=True,
            env=sanitized_environment(), check=False,
        )
    if result.returncode != 0:
        raise VerificationError(f"compiled FlukeEmbedder model load/interface/prediction failed: {result.stderr.strip()}")


def _ios_source_identity(repo_root: Path) -> tuple[str, str]:
    commit = _run_git(repo_root, ["rev-parse", "HEAD"])
    tree = _run_git(repo_root, ["rev-parse", "HEAD^{tree}"])
    relevant = ["App", "Packages", "AppStore/1.1", "scripts", "docs/app-store-1.1-submission.md"]
    if _run_git(repo_root, ["status", "--porcelain", "--untracked-files=all", "--", *relevant]):
        raise VerificationError("iOS release checkout has dirty or untracked submission inputs")
    return commit, tree


def _run_existing_archive_validators(repo_root: Path, archive: Path) -> None:
    commands = (
        [str(repo_root / "scripts/verify-archive-metadata.sh"), str(archive), BUNDLE_ID, "17.0"],
        [str(repo_root / "scripts/verify-app-store-archive.sh"), str(archive)],
    )
    for command in commands:
        result = subprocess.run(command, capture_output=True, text=True, env=sanitized_environment(), check=False)
        if result.returncode != 0:
            raise VerificationError(f"existing archive validator failed: {result.stderr.strip() or result.stdout.strip()}")


def verify_submission(repo_root: Path, model_checkout: Path, release: Path, archive: Path) -> None:
    validate_package(repo_root)
    validate_project(repo_root / "App/Fluke.xcodeproj/project.pbxproj")
    validate_xcode_build_settings(repo_root)
    validate_model_checkout_and_release(model_checkout, release)
    run_mobile_release_verifier(model_checkout, release)
    digests = validate_release_report(release)
    source_commit, source_tree = _ios_source_identity(repo_root)
    validate_archive(
        archive, release, digests, source_commit, source_tree,
        compiled_model_validator=validate_compiled_model,
    )
    _run_existing_archive_validators(repo_root, archive)


def main(arguments: list[str] | None = None) -> int:
    args = parse_arguments(arguments)
    repo_root = Path(__file__).resolve().parent.parent
    try:
        verify_submission(repo_root, args.model_checkout, args.release_directory, args.archive)
    except (OSError, UnicodeError, VerificationError) as error:
        print(f"App Store 1.1 verification failed: {error}", file=sys.stderr)
        return 1
    print("App Store 1.1 submission package and archive are valid for version 1.1 build 2")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
