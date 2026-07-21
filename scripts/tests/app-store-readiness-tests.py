#!/usr/bin/env python3
"""Repository-controlled App Store 1.1 readiness tests."""

from __future__ import annotations

import json
import importlib.util
from pathlib import Path
import plistlib
import re
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[2]


def load_script(name: str, relative_path: str):
    spec = importlib.util.spec_from_file_location(name, REPO_ROOT / relative_path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def replacing(value: dict, path: tuple[str, ...], replacement: object) -> dict:
    key, *remaining = path
    child = (
        replacing(value[key], tuple(remaining), replacement)
        if remaining
        else replacement
    )
    return {**value, key: child}


class SourceContractTests(unittest.TestCase):
    def test_release_target_is_exactly_version_1_1_build_2(self) -> None:
        project = (REPO_ROOT / "App/Fluke.xcodeproj/project.pbxproj").read_text()
        release = re.search(
            r"97C8ECF12FA59EE000BCF41D /\* Release \*/ = \{(.*?)\n\s*\};",
            project,
            re.DOTALL,
        )
        self.assertIsNotNone(release)
        self.assertIn("MARKETING_VERSION = 1.1;", release.group(1))
        self.assertIn("CURRENT_PROJECT_VERSION = 2;", release.group(1))

    def test_camera_copy_describes_local_live_analysis_and_explicit_upload(
        self,
    ) -> None:
        with (REPO_ROOT / "App/Fluke/Info.plist").open("rb") as source:
            camera_copy = plistlib.load(source)["NSCameraUsageDescription"].lower()
        for phrase in ("live camera", "on device", "only after you explicitly submit"):
            self.assertIn(phrase, camera_copy)

    def test_build_identity_phase_is_release_archive_only_and_pre_codesign(
        self,
    ) -> None:
        project = (REPO_ROOT / "App/Fluke.xcodeproj/project.pbxproj").read_text()
        self.assertIn("Generate Fluke Build Identity", project)
        self.assertIn("generate-build-identity.py", project)
        self.assertIn("FlukeBuildIdentity.plist", project)
        self.assertIn("SCRIPT_OUTPUT_FILE_0", project)
        self.assertIn('ACTION\\" != \\"install', project)


class BuildIdentityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.identity = load_script(
            "build_identity", "scripts/generate-build-identity.py"
        )

    def test_output_must_be_inside_derived_data(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            accepted = self.identity.require_output_under(
                root / "Build/identity.plist", root
            )
            self.assertEqual(accepted, (root / "Build/identity.plist").resolve())
            with self.assertRaisesRegex(
                self.identity.IdentityError, "inside DerivedData"
            ):
                self.identity.require_output_under(root.parent / "identity.plist", root)

    def test_release_requires_ready_report_bound_to_both_digests(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            release = Path(directory)
            package = release / "FlukeEmbedder.mlpackage"
            catalog = release / "catalog"
            package.mkdir()
            catalog.mkdir()
            (package / "model.mlmodel").write_bytes(b"model")
            (catalog / "manifest.json").write_text("{}")
            (catalog / "metadata.json").write_text("{}")
            (catalog / "references.f16").write_bytes(b"references")
            model_digest = self.identity.package_tree_sha256(package)
            catalog_digest = self.identity.sha256_file(catalog / "manifest.json")
            report = {
                "ready": True,
                "modelPackageSha256": model_digest,
                "catalogManifestSha256": catalog_digest,
            }
            (release / "mobile-release-report.json").write_text(json.dumps(report))
            self.assertEqual(
                self.identity.release_digests(release),
                (model_digest, catalog_digest),
            )
            report["ready"] = False
            (release / "mobile-release-report.json").write_text(json.dumps(report))
            with self.assertRaisesRegex(self.identity.IdentityError, "ready:true"):
                self.identity.release_digests(release)

    def test_dormant_release_pins_model_without_catalog_or_readiness(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            release = Path(directory)
            package = release / "FlukeEmbedder.mlpackage"
            package.mkdir()
            (package / "model.mlmodel").write_bytes(b"model")
            model_digest = self.identity.package_tree_sha256(package)
            report = {
                "ready": False,
                "modelPackageSha256": model_digest,
                "catalogManifestSha256": None,
            }
            (release / "mobile-release-report.json").write_text(json.dumps(report))
            self.assertEqual(
                self.identity.release_digests(release, "dormant"),
                (model_digest, ""),
            )
            report["modelPackageSha256"] = "0" * 64
            (release / "mobile-release-report.json").write_text(json.dumps(report))
            with self.assertRaisesRegex(
                self.identity.IdentityError, "model digest does not match"
            ):
                self.identity.release_digests(release, "dormant")

    def test_clean_checkout_provenance_rejects_untracked_files(self) -> None:
        import subprocess

        with tempfile.TemporaryDirectory() as directory:
            checkout = Path(directory)
            subprocess.run(["git", "init", "-q", str(checkout)], check=True)
            subprocess.run(
                [
                    "git",
                    "-C",
                    str(checkout),
                    "config",
                    "user.email",
                    "test@fluke.invalid",
                ],
                check=True,
            )
            subprocess.run(
                ["git", "-C", str(checkout), "config", "user.name", "Test"], check=True
            )
            (checkout / "tracked").write_text("value")
            subprocess.run(["git", "-C", str(checkout), "add", "tracked"], check=True)
            subprocess.run(
                ["git", "-C", str(checkout), "commit", "-qm", "fixture"], check=True
            )
            commit, tree = self.identity.require_clean_checkout(checkout, "test")
            self.assertRegex(commit, r"^[0-9a-f]{40}$")
            self.assertRegex(tree, r"^[0-9a-f]{40}$")
            (checkout / "untracked").write_text("dirty")
            with self.assertRaisesRegex(self.identity.IdentityError, "dirty"):
                self.identity.require_clean_checkout(checkout, "test")


class EvidenceContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.validator = load_script(
            "device_report", "scripts/verify-device-accessibility-report.py"
        )

    def test_device_report_template_is_deliberately_incomplete(self) -> None:
        report_path = (
            REPO_ROOT / "AppStore/1.1/evidence/device-accessibility-report.json"
        )
        report = json.loads(report_path.read_text())
        self.assertEqual(report["status"], "incomplete")
        self.assertFalse(report["physicalDeviceEvidenceComplete"])

    def test_model_card_references_authoritative_release_without_metrics(self) -> None:
        text = (REPO_ROOT / "docs/ios-model-card.md").read_text().lower()
        self.assertIn("mobile-release-report.json", text)
        self.assertIn("6fe4767cd1c5716a04b655c9eaac4bd745471569", text)
        self.assertNotRegex(text, r"top[- ]?1\s*[:=]\s*\d")

    def test_metadata_discloses_dormant_matching_without_claims(self) -> None:
        metadata = json.loads(
            (REPO_ROOT / "AppStore/1.1/en-US/metadata.json").read_text()
        )
        review_notes = metadata["reviewNotes"].lower()
        self.assertIn("dormant", review_notes)
        self.assertIn("no identification claims", review_notes)
        self.assertIn("live camera framing preview", review_notes)
        self.assertNotIn("selected suggestion", review_notes)

    @staticmethod
    def complete_report() -> dict:
        return {
            "schemaVersion": 1,
            "status": "complete",
            "physicalDeviceEvidenceComplete": True,
            "release": {"marketingVersion": "1.1", "buildNumber": "2"},
            "provenance": {
                "sourceCommit": "1" * 40,
                "sourceTree": "2" * 40,
                "modelSourceCommit": "3" * 40,
                "modelSourceTree": "4" * 40,
                "archiveSha256": "5" * 64,
                "evidenceDigests": ["6" * 64],
            },
            "device": {
                "model": "iPhone",
                "iosVersion": "26.0",
                "runAtUtc": "2026-07-19T00:00:00Z",
            },
            "performance": {
                "coldLatencyMs": {"p50": 200, "p95": 450},
                "warmLatencyMs": {"p50": 100, "p95": 300},
                "peakMemoryMB": 128,
                "appSizeBytes": 1000,
                "binarySizeBytes": 500,
                "sustainedRunSeconds": 120,
                "maxRetainedFrames": 1,
            },
            "runtime": {
                "thermalStateAcceptable": True,
                "previewContinuous": True,
                "backgroundSuspendsCamera": True,
                "airplaneModeIdentificationWorks": True,
                "airplaneModeSubmissionQueues": True,
                "identifierNetworkRequestCount": 0,
            },
            "accessibility": {
                "voiceOver": True,
                "dynamicTypeXXXL": True,
                "contrast": True,
                "reduceMotion": True,
                "cameraPermissionDenied": True,
                "photoPermissionDenied": True,
            },
        }

    def test_complete_physical_device_report_passes_thresholds(self) -> None:
        report = self.complete_report()
        self.validator.validate(report)
        slow_report = replacing(report, ("performance", "warmLatencyMs", "p95"), 501)
        with self.assertRaisesRegex(self.validator.ReportError, "<= 500"):
            self.validator.validate(slow_report)

    def test_device_report_rejects_every_unverified_evidence_class(self) -> None:
        report = self.complete_report()
        failures = (
            (("schemaVersion",), 2, "schemaVersion"),
            (("status",), "incomplete", "incomplete"),
            (("release", "buildNumber"), "3", "version 1.1"),
            (("provenance", "sourceCommit"), "short", "full git SHA"),
            (("provenance", "archiveSha256"), "short", "SHA-256"),
            (("provenance", "evidenceDigests"), [], "evidenceDigests"),
            (("device", "model"), "", "device identity"),
            (("performance", "coldLatencyMs"), None, "latency evidence"),
            (("performance", "peakMemoryMB"), 0, "peakMemoryMB"),
            (("performance", "sustainedRunSeconds"), 119, "at least 120"),
            (("performance", "maxRetainedFrames"), 2, "at most one"),
            (("runtime", "previewContinuous"), False, "airplane-mode cases"),
            (("runtime", "identifierNetworkRequestCount"), 1, "zero network"),
            (("accessibility", "voiceOver"), False, "accessibility"),
        )
        for path, value, message in failures:
            with self.subTest(path=path), self.assertRaisesRegex(
                self.validator.ReportError, message
            ):
                self.validator.validate(replacing(report, path, value))


class ScreenshotContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.validator = load_script(
            "screenshot_provenance", "scripts/verify-screenshot-provenance.py"
        )

    def test_capture_defaults_to_1_1_and_writes_provenance(self) -> None:
        capture = (REPO_ROOT / "scripts/capture-app-store-screenshots.sh").read_text()
        self.assertIn("AppStore/1.1/en-US/screenshots/6.9-inch", capture)
        self.assertIn("screenshot-provenance.json", capture)
        self.assertNotIn("https://fluke-api.onrender.com/api/v1/health", capture)

    def test_fixture_does_not_claim_a_production_identification(self) -> None:
        fixture = (REPO_ROOT / "App/Fluke/AppStoreScreenshotFixtures.swift").read_text()
        self.assertIn("Preview fixture", fixture)
        self.assertIn(
            '#"{"accounts":true,"identification":false,"submissions":true}"#', fixture
        )

    def test_provenance_binds_exact_images_fixture_and_artifacts(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            screenshots = repo / "screenshots"
            fixture = repo / "App/Fluke/AppStoreScreenshotFixtures.swift"
            screenshots.mkdir(parents=True)
            fixture.parent.mkdir(parents=True)
            fixture.write_text("Preview fixture")
            for index, name in enumerate(self.validator.EXPECTED_NAMES):
                (screenshots / name).write_bytes(f"image-{index}".encode())
            fake_identity = SimpleNamespace(
                MODEL_SOURCE_COMMIT="3" * 40,
                MODEL_SOURCE_TREE="4" * 40,
                git=lambda *_: "2" * 40,
                require_clean_checkout=lambda *_: ("3" * 40, "4" * 40),
                release_digests=lambda *_: ("5" * 64, "6" * 64),
            )
            arguments = SimpleNamespace(
                repo=repo,
                screenshots=screenshots,
                manifest=repo / "manifest.json",
                model_checkout=repo,
                release=repo,
                source_commit="1" * 40,
                source_tree="2" * 40,
                runtime="iOS-26-0",
                device="iPhone",
            )
            with mock.patch.object(
                self.validator, "load_identity_module", return_value=fake_identity
            ):
                payload = self.validator.create(arguments)
                arguments.manifest.write_text(json.dumps(payload))
                self.validator.verify(arguments)
            self.assertEqual(
                tuple(payload["screenshots"]), self.validator.EXPECTED_NAMES
            )
            self.assertFalse(payload["fixtureSource"]["identificationEnabled"])


class ArchiveContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.validator = load_script(
            "archive_runtime", "scripts/verify-archive-runtime.py"
        )

    def test_archive_orchestrator_has_explicit_non_upload_and_upload_modes(
        self,
    ) -> None:
        script = (REPO_ROOT / "scripts/archive-app-store-1-1.sh").read_text()
        self.assertIn("--dry-run", script)
        self.assertIn("--upload", script)
        self.assertIn("verify-app-store-1-1-submission.sh", script)
        self.assertIn("ASC_KEY_ID", script)

    def test_runtime_allowlist_is_repository_controlled(self) -> None:
        allowlist = json.loads(
            (REPO_ROOT / "AppStore/1.1/runtime-dependency-allowlist.json").read_text()
        )
        self.assertEqual(allowlist["schemaVersion"], 1)
        self.assertEqual(allowlist["telemetryFrameworks"], [])
        self.assertEqual(allowlist["identifierTransportArtifacts"], [])

    def test_runtime_scan_rejects_telemetry_and_identifier_transport(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / "Fluke.xcarchive"
            app = archive / "Products/Applications/Fluke.app"
            app.mkdir(parents=True)
            with (archive / "Info.plist").open("wb") as output:
                plistlib.dump(
                    {
                        "ApplicationProperties": {
                            "ApplicationPath": "Applications/Fluke.app"
                        }
                    },
                    output,
                )
            allowlist = root / "allowlist.json"
            allowlist.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "purpose": "test",
                        "frameworks": [],
                        "telemetryFrameworks": [],
                        "identifierTransportArtifacts": [],
                    }
                )
            )
            self.validator.validate(archive, allowlist)
            (app / "TelemetryDeck.bin").write_bytes(b"telemetrydeck")
            with self.assertRaisesRegex(
                self.validator.RuntimeError, "forbidden runtime"
            ):
                self.validator.validate(archive, allowlist)
            (app / "TelemetryDeck.bin").unlink()
            (app / "Safe.bin").write_bytes(b"linked SentrySDK marker")
            with self.assertRaisesRegex(
                self.validator.RuntimeError, "telemetry marker"
            ):
                self.validator.validate(archive, allowlist)
            (app / "Safe.bin").write_bytes(b"POST /api/v1/identify")
            with self.assertRaisesRegex(
                self.validator.RuntimeError, "identifier transport"
            ):
                self.validator.validate(archive, allowlist)


if __name__ == "__main__":
    unittest.main()
