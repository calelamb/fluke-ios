#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$repo_root" <<'PY'
from __future__ import annotations

import hashlib
import importlib.machinery
import ast
import json
import os
from pathlib import Path
import plistlib
import py_compile
import shutil
import subprocess
import sys
import tempfile

repo = Path(sys.argv[1])
verifier_path = repo / "scripts/verify-app-store-1-1-submission.sh"
sys.dont_write_bytecode = True
module = importlib.machinery.SourceFileLoader("app_store_1_1_verifier", str(verifier_path)).load_module()
failures = []

def check(name, action, expected=None):
    try:
        action()
    except Exception as error:
        if expected is None:
            failures.append(f"{name}: unexpected failure: {error}")
        elif expected not in str(error):
            failures.append(f"{name}: expected {expected!r}, got {error!r}")
    else:
        if expected is not None:
            failures.append(f"{name}: unexpectedly succeeded")

def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    if isinstance(data, bytes):
        path.write_bytes(data)
    else:
        path.write_text(data, encoding="utf-8")

def package_digest(root):
    digest = hashlib.sha256(b"fluke-coreml-package-v1\0")
    for path in sorted(root.rglob("*"), key=lambda value: value.relative_to(root).as_posix()):
        relative = path.relative_to(root).as_posix().encode()
        digest.update(b"D" if path.is_dir() else b"F")
        digest.update(len(relative).to_bytes(8, "big"))
        digest.update(relative)
        if path.is_file():
            digest.update(path.read_bytes())
    return digest.hexdigest()

def make_release(root):
    package = root / "FlukeEmbedder.mlpackage"
    write(package / "Data/model.bin", b"model")
    write(root / "catalog/manifest.json", b'{"catalog":1}\n')
    write(root / "catalog/metadata.json", b'{"individuals":[]}\n')
    write(root / "catalog/references.f16", b"vectors")
    return {
        "model": package_digest(package),
        "catalog": hashlib.sha256((root / "catalog/manifest.json").read_bytes()).hexdigest(),
    }

def make_archive(root, release, identity):
    app = root / "Products/Applications/Fluke.app"
    app.mkdir(parents=True)
    archive_info = {
        "ApplicationProperties": {
            "ApplicationPath": "Applications/Fluke.app",
            "CFBundleIdentifier": "app.fluke.Fluke",
            "CFBundleShortVersionString": "1.1",
            "CFBundleVersion": "2",
            "SigningIdentity": "Apple Distribution: Cale Lamb (86RBV2JZ8F)",
        }
    }
    app_info = {
        "CFBundleIdentifier": "app.fluke.Fluke",
        "CFBundleShortVersionString": "1.1",
        "CFBundleVersion": "2",
    }
    for path, value in ((root / "Info.plist", archive_info), (app / "Info.plist", app_info),
                        (app / "FlukeBuildIdentity.plist", identity)):
        with path.open("wb") as output:
            plistlib.dump(value, output)
    for name in ("manifest.json", "metadata.json", "references.f16"):
        destination = app / "IdentifierCatalog" / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(release / "catalog" / name, destination)
    write(app / "FlukeEmbedder.mlmodelc/model.mil", b"compiled")
    return app

def project_fixture(version, build, second_exception=False):
    exception = ""
    if second_exception:
        exception = """E2 /* hidden */ = {
  isa = PBXFileSystemSynchronizedBuildFileExceptionSet;
  membershipExceptions = ( IdentifierCatalog/references.f16, );
  target = AAA /* Fluke */;
};"""
    return f"""
AAA /* Fluke */ = {{
  isa = PBXNativeTarget;
  buildConfigurationList = BEEF /* Build configuration list for PBXNativeTarget \"Fluke\" */;
  buildPhases = ( EEEE /* Resources */, );
  fileSystemSynchronizedGroups = ( D00D /* Fluke */, );
}};
D00D /* Fluke */ = {{
  isa = PBXFileSystemSynchronizedRootGroup;
  path = Fluke;
}};
{exception}
CAFE /* Release */ = {{
  isa = XCBuildConfiguration;
  buildSettings = {{ CURRENT_PROJECT_VERSION = {build}; MARKETING_VERSION = {version}; PRODUCT_BUNDLE_IDENTIFIER = {module.BUNDLE_ID}; }};
  name = Release;
}};
BEEF /* Build configuration list for PBXNativeTarget "Fluke" */ = {{
  isa = XCConfigurationList;
  buildConfigurations = ( CAFE /* Release */, );
}};
EEEE /* Resources */ = {{
  isa = PBXResourcesBuildPhase;
}};
"""

with tempfile.TemporaryDirectory(prefix="fluke-app-store-tests.") as temporary:
    root = Path(temporary)

    check("production parser has exactly three immutable inputs",
          lambda: module.parse_arguments(["model", "release", "archive"]))
    check("fixture flags are not accepted",
          lambda: module.parse_arguments(["--build-settings-fixture", "x"]), "usage")
    os.environ["FLUKE_APP_STORE_TESTING"] = "true"
    check("fixture environment cannot unlock production parser",
          lambda: module.parse_arguments(["--shipping-resources-fixture", "x"]), "usage")
    del os.environ["FLUKE_APP_STORE_TESTING"]

    environment = module.sanitized_environment()
    if "XCODE_XCCONFIG_FILE" in environment or environment.get("PATH") != "/usr/bin:/bin":
        failures.append("sanitized environment retains ambient Xcode or PATH overrides")

    bytecode_source = root / "bytecode-source"
    bytecode_cache = root / "trusted-bytecode-cache"
    bytecode_marker = root / "poisoned-pyc-ran"
    write(bytecode_source / "victim.py", f"from pathlib import Path\nPath({str(bytecode_marker)!r}).touch()\n")
    py_compile.compile(
        str(bytecode_source / "victim.py"),
        invalidation_mode=py_compile.PycInvalidationMode.UNCHECKED_HASH,
    )
    write(bytecode_source / "victim.py", "VALUE = 'trusted-source'\n")
    check("fresh bytecode prefix environment is available",
          lambda: module.verifier_environment(bytecode_cache))
    try:
        bytecode_environment = module.verifier_environment(bytecode_cache)
        bytecode_environment["PYTHONPATH"] = str(bytecode_source)
        bytecode_probe = subprocess.run(
            ["/usr/bin/python3", "-c", "import victim; print(victim.VALUE)"],
            capture_output=True, text=True, env=bytecode_environment, check=False,
        )
        if bytecode_probe.returncode != 0 or bytecode_marker.exists() or bytecode_probe.stdout.strip() != "trusted-source":
            failures.append("poisoned valid-header source pyc executed outside a fresh trusted prefix")
    except Exception:
        pass
    fake_bin = root / "fake-bin"
    fake_uv = fake_bin / "uv"
    write(fake_uv, "#!/bin/sh\nexit 0\n")
    fake_uv.chmod(0o755)
    original_path = os.environ.get("PATH", "")
    os.environ["PATH"] = f"{fake_bin}:{original_path}"
    check("PATH-spoofed uv is rejected by executable digest",
          module._find_uv, "pinned release-tool identity")
    os.environ["PATH"] = original_path

    safe = root / "safe.json"
    write(safe, '{"ok":true}\n')
    check("regular JSON is readable", lambda: module.read_json_no_follow(safe, "test JSON"))
    linked_json = root / "linked.json"
    linked_json.symlink_to(safe)
    check("symlinked package JSON is rejected",
          lambda: module.read_json_no_follow(linked_json, "test JSON"), "symbolic link")
    linked_schema = root / "schema.json"
    linked_schema.symlink_to(safe)
    check("symlinked package schema is rejected",
          lambda: module.read_json_no_follow(linked_schema, "test schema"), "symbolic link")

    check("checked-in package remains blocked without fabricated screenshots",
          lambda: module.validate_package(repo), "requires 1-10 accepted opaque 6.9-inch screenshots")
    direct = subprocess.run(
        [str(verifier_path), "/nonexistent/model", "/nonexistent/release", "/nonexistent/archive"],
        capture_output=True,
        text=True,
        check=False,
    )
    if direct.returncode != 1 or "requires 1-10 accepted opaque 6.9-inch screenshots" not in direct.stderr:
        failures.append("Python verifier is not directly executable under its historical .sh name")
    hostile_bin = root / "hostile-bin"
    hostile_python = hostile_bin / "python3"
    write(hostile_python, "#!/bin/sh\nexit 0\n")
    hostile_python.chmod(0o755)
    hostile_environment = {**os.environ, "PATH": f"{hostile_bin}:/usr/bin:/bin"}
    hostile_launch = subprocess.run(
        [str(verifier_path), "/nonexistent/model", "/nonexistent/release", "/nonexistent/archive"],
        capture_output=True,
        text=True,
        env=hostile_environment,
        check=False,
    )
    if hostile_launch.returncode == 0:
        failures.append("hostile PATH python3 bypassed the direct production launcher")

    check("verifier source parses under the trusted platform Python 3.9 grammar",
          lambda: ast.parse(verifier_path.read_text(encoding="utf-8"), feature_version=(3, 9)))
    if "stat(follow_symlinks=" in verifier_path.read_text(encoding="utf-8"):
        failures.append("verifier uses Path.stat(follow_symlinks=), unavailable on platform Python 3.9")
    check("schema minLength rejects empty metadata values",
          lambda: module._validate_schema("", {"type": "string", "minLength": 1}), "too short")

    screenshot = root / "screen.png"
    shutil.copyfile(repo / "AppStore/1.0/en-US/screenshots/6.9-inch/01-sightings.png", screenshot)
    denylist = module.screenshot_digest_denylist(repo / "AppStore/1.0")
    check("1.0 screenshot digest reuse is rejected",
          lambda: module.validate_screenshot_path(screenshot, denylist), "reuses a 1.0 screenshot")
    linked_screenshot = root / "linked-screen.png"
    linked_screenshot.symlink_to(screenshot)
    check("symlinked screenshot is rejected",
          lambda: module.validate_screenshot_path(linked_screenshot, set()), "symbolic link")

    release = root / "release"
    digests = make_release(release)
    identity = {
        "schemaVersion": 1,
        "sourceCommit": "1" * 40,
        "sourceTree": "2" * 40,
        "modelSourceCommit": module.MODEL_SOURCE_COMMIT,
        "modelSourceTree": module.MODEL_SOURCE_TREE,
        "marketingVersion": "1.1",
        "buildNumber": "2",
        "modelPackageSha256": digests["model"],
        "catalogManifestSha256": digests["catalog"],
    }
    archive = root / "Fluke.xcarchive"
    app = make_archive(archive, release, identity)
    valid_codesign = """Authority=Apple Distribution: Cale Lamb (86RBV2JZ8F)
Authority=Apple Worldwide Developer Relations Certification Authority
Authority=Apple Root CA
TeamIdentifier=86RBV2JZ8F
"""
    valid_entitlements = {
        "application-identifier": "86RBV2JZ8F.app.fluke.Fluke",
        "com.apple.developer.team-identifier": "86RBV2JZ8F",
        "get-task-allow": False,
    }
    valid_profile = {
        "TeamIdentifier": ["86RBV2JZ8F"],
        "ApplicationIdentifierPrefix": ["86RBV2JZ8F"],
        "Entitlements": valid_entitlements,
        "ProvisionsAllDevices": False,
    }
    check("captured Apple Distribution signing evidence is accepted",
          lambda: module.validate_signing_evidence(valid_codesign, valid_entitlements, valid_profile))
    development_codesign = valid_codesign.replace("Apple Distribution:", "Apple Development:")
    development_entitlements = {**valid_entitlements, "get-task-allow": True}
    development_profile = {**valid_profile, "Entitlements": development_entitlements}
    check("development-signed app with forged archive identity is rejected",
          lambda: module.validate_signing_evidence(
              development_codesign, development_entitlements, development_profile
          ), "Apple Distribution")
    wrong_team_codesign = valid_codesign.replace("86RBV2JZ8F", "AAAAAAAAAA")
    check("other-team distribution signature is rejected",
          lambda: module.validate_signing_evidence(
              wrong_team_codesign, valid_entitlements, valid_profile
          ), "team")
    check("archive structure binds catalog and build identity",
          lambda: module.validate_archive(
              archive, release, digests, "1" * 40, "2" * 40,
              compiled_model_validator=lambda _: None,
          ))

    unsigned = root / "unsigned.xcarchive"
    shutil.copytree(archive, unsigned)
    with (unsigned / "Info.plist").open("rb") as source:
        unsigned_info = plistlib.load(source)
    del unsigned_info["ApplicationProperties"]["SigningIdentity"]
    with (unsigned / "Info.plist").open("wb") as output:
        plistlib.dump(unsigned_info, output)
    check("unsigned archive is rejected before attestation trust",
          lambda: module.validate_signing_evidence("", {}, {}), "Apple Distribution")

    forged_root_identity = root / "forged-root-identity.xcarchive"
    shutil.copytree(archive, forged_root_identity)
    (forged_root_identity / "Products/Applications/Fluke.app/FlukeBuildIdentity.plist").unlink()
    with (forged_root_identity / "FlukeBuildIdentity.plist").open("wb") as output:
        plistlib.dump(identity, output)
    check("unsigned archive-root identity cannot replace signed in-app attestation",
          lambda: module.validate_archive(
              forged_root_identity, release, digests, "1" * 40, "2" * 40,
              compiled_model_validator=lambda _: None,
          ), "signed app build identity")
    check("compiled model validator loads Core ML rather than trusting membership",
          lambda: module.validate_compiled_model(app / "FlukeEmbedder.mlmodelc"),
          "compiled FlukeEmbedder model load/interface/prediction failed")

    source_only = root / "source-only.xcarchive"
    shutil.copytree(archive, source_only)
    shutil.rmtree(source_only / "Products/Applications/Fluke.app/FlukeEmbedder.mlmodelc")
    write(source_only / "Products/Applications/Fluke.app/Models/FlukeEmbedder.mlpackage/Manifest.json", "{}")
    check("source model membership cannot replace compiled archive model",
          lambda: module.validate_archive(
              source_only, release, digests, "1" * 40, "2" * 40,
              compiled_model_validator=lambda _: None,
          ), "compiled FlukeEmbedder.mlmodelc")

    linked_catalog_archive = root / "linked-catalog.xcarchive"
    shutil.copytree(archive, linked_catalog_archive)
    linked_catalog = linked_catalog_archive / "Products/Applications/Fluke.app/IdentifierCatalog/manifest.json"
    linked_catalog.unlink()
    linked_catalog.symlink_to(release / "catalog/manifest.json")
    check("symlinked archived catalog is rejected",
          lambda: module.validate_archive(
              linked_catalog_archive, release, digests, "1" * 40, "2" * 40,
              compiled_model_validator=lambda _: None,
          ), "symbolic link")

    linked_model_archive = root / "linked-model.xcarchive"
    shutil.copytree(archive, linked_model_archive)
    linked_model = linked_model_archive / "Products/Applications/Fluke.app/FlukeEmbedder.mlmodelc"
    shutil.rmtree(linked_model)
    linked_model.symlink_to(app / "FlukeEmbedder.mlmodelc", target_is_directory=True)
    check("symlinked compiled model is rejected",
          lambda: module.validate_archive(
              linked_model_archive, release, digests, "1" * 40, "2" * 40,
              compiled_model_validator=lambda _: None,
          ), "symbolic link")

    duplicate_model_archive = root / "duplicate-model.xcarchive"
    shutil.copytree(archive, duplicate_model_archive)
    duplicate = duplicate_model_archive / "Products/Applications/Fluke.app/Frameworks/Nested/FlukeEmbedder.mlmodelc"
    write(duplicate / "model.mil", b"duplicate")
    check("recursive duplicate compiled models are rejected",
          lambda: module.validate_archive(
              duplicate_model_archive, release, digests, "1" * 40, "2" * 40,
              compiled_model_validator=lambda _: None,
          ), "exactly one compiled FlukeEmbedder.mlmodelc")

    wrong_identity = root / "wrong-identity.xcarchive"
    shutil.copytree(archive, wrong_identity)
    wrong_identity_path = wrong_identity / "Products/Applications/Fluke.app/FlukeBuildIdentity.plist"
    with wrong_identity_path.open("rb") as source:
        changed = plistlib.load(source)
    changed["sourceCommit"] = "f" * 40
    with wrong_identity_path.open("wb") as output:
        plistlib.dump(changed, output)
    check("archive source identity is exact",
          lambda: module.validate_archive(
              wrong_identity, release, digests, "1" * 40, "2" * 40,
              compiled_model_validator=lambda _: None,
          ), "sourceCommit")

    pbx = root / "project.pbxproj"
    write(pbx, project_fixture(version="1.1", build="2"))
    check("direct Fluke Release settings are accepted", lambda: module.validate_project(pbx))
    write(pbx, project_fixture(version="1.0", build="1"))
    check("direct Fluke Release version is pinned",
          lambda: module.validate_project(pbx), "MARKETING_VERSION")
    write(pbx, project_fixture(version="1.1", build="2", second_exception=True))
    check("a second synchronized exception set cannot hide catalog resources",
          lambda: module.validate_project(pbx), "membership exception")
    check("checked-in Fluke Release target remains blocked at 1.0 build 1",
          lambda: module.validate_project(repo / "App/Fluke.xcodeproj/project.pbxproj"),
          "MARKETING_VERSION")

    linked_release = root / "linked-release"
    linked_release.symlink_to(release, target_is_directory=True)
    check("symlinked release directory is rejected",
          lambda: module.validate_model_checkout_and_release(root, linked_release), "symbolic link")

    model_checkout = repo.parents[2] / "fluke-model/.worktrees/on-device-coreml-release"
    if model_checkout.is_dir():
        check("reviewed model checkout provenance is accepted",
              lambda: module.validate_model_checkout_and_release(model_checkout, release))
        dirty_checkout = root / "dirty-model-checkout"
        subprocess.run(
            ["/usr/bin/git", "clone", "--quiet", "--shared", str(model_checkout), str(dirty_checkout)],
            check=True,
        )
        write(dirty_checkout / "src/untracked-verifier-input.py", "untracked\n")
        check("dirty relevant model checkout is rejected",
              lambda: module.validate_model_checkout_and_release(dirty_checkout, release),
              "dirty or untracked verifier inputs")
        poisoned_venv = model_checkout / ".venv/bin/python"
        check("isolated verifier command never executes the ignored checkout venv",
              lambda: module.mobile_release_command(model_checkout, release, module._find_uv()),
              None)
        try:
            isolated_command = module.mobile_release_command(model_checkout, release, module._find_uv())
            rendered = " ".join(str(value) for value in isolated_command)
            if "--isolated" not in isolated_command or "--no-cache" not in isolated_command or str(poisoned_venv) in rendered:
                failures.append("mobile release command is not isolated from the ignored checkout venv")
        except Exception:
            pass
        poison_root = root / "poison-smoke"
        poison_marker = poison_root / "poison-ran"
        poison_python = poison_root / ".venv/bin/python"
        write(poison_python, f"#!/bin/sh\ntouch '{poison_marker}'\nexit 0\n")
        poison_python.chmod(0o755)
        uv = module._find_uv()
        model_python = module._find_model_python(uv)
        check("complete managed Python distribution matches pinned tree digest",
              lambda: module.authenticate_model_python(model_python))
        fake_distribution = root / "mutated-python"
        fake_python = fake_distribution / "bin/python3.11"
        write(fake_python, b"launcher")
        fake_python.chmod(0o755)
        write(fake_distribution / "lib/python3.11/os.py", "MUTATED = True\n")
        check("managed Python sibling stdlib mutation is rejected",
              lambda: module.authenticate_model_python(fake_python),
              "distribution tree")
        isolated_smoke = subprocess.run(
            [
                str(uv), "--no-cache", "--no-config", "run", "--isolated", "--no-project",
                "--python", str(model_python), "--no-python-downloads", "python", "-c",
                "print('isolated')",
            ],
            cwd=poison_root,
            capture_output=True,
            text=True,
            env=module.sanitized_environment(),
            check=False,
        )
        if isolated_smoke.returncode != 0 or poison_marker.exists():
            failures.append("uv isolated execution invoked the poisoned checkout .venv")
        with tempfile.TemporaryDirectory(prefix=".appstore-model-test.", dir=repo) as model_temporary:
            hand_authored = Path(model_temporary)
            write(hand_authored / "mobile-release-report.json", json.dumps({"ready": True}))
            def authoritative_overwrite():
                try:
                    module.run_mobile_release_verifier(model_checkout, hand_authored)
                except module.VerificationError as error:
                    regenerated = json.loads((hand_authored / "mobile-release-report.json").read_text())
                    if regenerated.get("ready") is not False or regenerated.get("schemaVersion") != 1:
                        raise AssertionError("actual locked verifier did not overwrite ready:true")
                    if "fresh mobile release verification failed" not in str(error):
                        raise
                    return
                raise AssertionError("evidence-free release unexpectedly passed")
            check("actual locked model verifier overwrites preexisting ready:true report",
                  authoritative_overwrite)
    else:
        failures.append(f"reviewed model checkout not found at {model_checkout}")

if failures:
    print("\n".join(f"FAIL: {failure}" for failure in failures), file=sys.stderr)
    raise SystemExit(1)
print("App Store 1.1 submission verifier tests passed")
PY
