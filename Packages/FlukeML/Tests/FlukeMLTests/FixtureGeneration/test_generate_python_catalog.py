"""Fail-closed provenance tests for the cross-language fixture generator."""

from __future__ import annotations

import importlib.util
import subprocess  # nosec B404
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

GENERATOR_PATH = Path(__file__).with_name("generate_python_catalog.py")
SPEC = importlib.util.spec_from_file_location("fluke_fixture_generator", GENERATOR_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("fixture generator could not be loaded")
generator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(generator)


class FixtureGeneratorProvenanceTests(unittest.TestCase):
    def test_dirty_producer_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            module = root / "src/fluke_model/mobile_catalog.py"
            module.parent.mkdir(parents=True)
            module.write_text("", encoding="utf-8")
            results = (
                subprocess.CompletedProcess(
                    [], 0, generator.PRODUCER_COMMIT + "\n", ""
                ),
                subprocess.CompletedProcess(
                    [], 0, " M src/fluke_model/mobile_catalog.py\n", ""
                ),
            )
            with (
                mock.patch.object(generator.shutil, "which", return_value="git"),
                mock.patch.object(generator.subprocess, "run", side_effect=results),
            ):
                with self.assertRaisesRegex(RuntimeError, "must be clean"):
                    generator._verify_producer(root)

    def test_verified_source_wins_over_ambient_pythonpath(self) -> None:
        with (
            tempfile.TemporaryDirectory() as verified_directory,
            tempfile.TemporaryDirectory() as ambient_directory,
        ):
            verified = Path(verified_directory)
            ambient = Path(ambient_directory)
            for root, marker in ((verified, "verified"), (ambient, "ambient")):
                package = root / "fluke_model"
                package.mkdir()
                (package / "__init__.py").write_text("", encoding="utf-8")
                (package / "mobile_catalog.py").write_text(
                    f"ORIGIN = {marker!r}\n", encoding="utf-8"
                )
            sys.path.insert(0, str(ambient))
            try:
                imported = generator._import_producer(verified)
            finally:
                sys.path.remove(str(ambient))
            self.assertEqual(imported.ORIGIN, "verified")
            self.assertTrue(
                Path(imported.__file__).resolve().is_relative_to(verified.resolve())
            )


if __name__ == "__main__":
    unittest.main()
