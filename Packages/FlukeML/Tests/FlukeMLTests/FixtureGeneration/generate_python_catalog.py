"""Generate the checked-in Swift contract fixture with the pinned Python producer."""

from __future__ import annotations

import argparse
import hashlib
import importlib
import json
import shutil

# Safe here: the fixed-argument git invocation only verifies pinned provenance.
import subprocess  # nosec B404
import sys
from functools import reduce
from pathlib import Path
from types import ModuleType

import numpy as np

PRODUCER_COMMIT = "7aa6474ca51c4c7e91cd4552093e7cc3424924b2"
DIMENSION = 384
MODEL_REVISION = "ed25f3a31f01632728cabb09d1542f84ab7b0056"
MODEL_SHA256 = "a" * 64
SCORE_INPUTS = (
    ("ref-001", "whale-j35", "J35", 1.00),
    ("ref-002", "whale-j35", "J35", 0.98),
    ("ref-003", "whale-j35", "J35", 0.96),
    ("ref-004", "whale-j35", "J35", 0.10),
    ("ref-005", "whale-j27", "J27", 0.90),
    ("ref-006", "whale-j27", "J27", 0.88),
    ("ref-007", "whale-t049a", "T049A", 0.80),
)


def _arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--producer-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def _verify_producer(root: Path) -> Path:
    git = shutil.which("git")
    if git is None:
        raise RuntimeError("git is required to verify producer provenance")
    # No shell is involved; only the user-selected repository path varies.
    head = subprocess.run(  # nosec
        [git, "-C", str(root), "rev-parse", "HEAD"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    if head != PRODUCER_COMMIT:
        raise RuntimeError(f"expected producer {PRODUCER_COMMIT}, found {head}")
    status = subprocess.run(  # nosec
        [git, "-C", str(root), "status", "--porcelain", "--untracked-files=all"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    if status:
        raise RuntimeError("producer worktree must be clean")
    source_root = (root / "src").resolve(strict=True)
    module_path = (source_root / "fluke_model/mobile_catalog.py").resolve(strict=True)
    if not module_path.is_relative_to(source_root) or not module_path.is_file():
        raise RuntimeError("producer module must be a regular file under producer src")
    return source_root


def _import_producer(source_root: Path) -> ModuleType:
    verified_source = source_root.resolve(strict=True)
    for name in tuple(sys.modules):
        if name == "fluke_model" or name.startswith("fluke_model."):
            del sys.modules[name]
    sys.path.insert(0, str(verified_source))
    importlib.invalidate_caches()
    try:
        module = importlib.import_module("fluke_model.mobile_catalog")
    finally:
        sys.path.pop(0)
    module_file = Path(module.__file__ or "").resolve(strict=True)
    if not module_file.is_relative_to(verified_source):
        raise RuntimeError("producer module did not load from verified producer src")
    return module


def _unit_vector(score: float) -> np.ndarray:
    second = np.sqrt(max(0.0, 1.0 - score * score))
    return np.array(
        (score, second, *(0.0 for _ in range(DIMENSION - 2))), dtype=np.float32
    )


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _golden(output: Path) -> dict[str, object]:
    rows = json.loads((output / "metadata.json").read_text(encoding="utf-8"))
    vectors = np.fromfile(output / "references.f16", dtype="<f2").astype(np.float32)
    matrix = vectors.reshape(len(rows), DIMENSION)
    scores = matrix[:, 0]
    references = sorted(
        zip(rows, scores, strict=True),
        key=lambda pair: (-float(pair[1]), pair[0]["referencePhotoId"]),
    )[:25]
    catalog_ids = tuple(sorted({row["catalogId"] for row, _ in references}))

    def identity(catalog_id: str) -> dict[str, object]:
        best = tuple(pair for pair in references if pair[0]["catalogId"] == catalog_id)[
            :3
        ]
        total = reduce(
            lambda accumulated, pair: np.float32(accumulated + pair[1]),
            best,
            np.float32(0),
        )
        return {
            "catalogId": catalog_id,
            "whaleId": best[0][0]["whaleId"],
            "score": float(np.float32(total / np.float32(len(best)))),
            "referencePhotoIds": [row["referencePhotoId"] for row, _ in best],
        }

    identities = tuple(identity(catalog_id) for catalog_id in catalog_ids)
    ranked = sorted(
        identities,
        key=lambda item: (
            -float(item["score"]),
            str(item["catalogId"]),
            str(item["whaleId"]),
        ),
    )
    return {"query": {"firstValue": 1.0, "remainingValues": 0.0}, "identities": ranked}


def main() -> None:
    arguments = _arguments()
    producer_root = arguments.producer_root.resolve(strict=True)
    output = arguments.output.resolve(strict=False)
    producer_source = _verify_producer(producer_root)
    producer = _import_producer(producer_source)

    rows = tuple(
        producer.ReferenceRow(
            reference_id, whale_id, catalog_id, "synthetic-owned-fixture"
        )
        for reference_id, whale_id, catalog_id, _ in SCORE_INPUTS
    )
    embeddings = np.stack(tuple(_unit_vector(score) for *_, score in SCORE_INPUTS))
    release = producer.MobileCatalogRelease(
        manifest_version="2026-07-18",
        model_id="facebook/dinov2-small",
        model_revision=MODEL_REVISION,
        model_version="dinov2-small-coreml-v1",
        model_sha256=MODEL_SHA256,
        preprocessing_version="dinov2-imagenet-v1",
        embedding_dimension=DIMENSION,
        index_version="mobile-reference-v1",
        minimum_app_build=1,
        maximum_app_build=100,
        score_semantics=producer.SCORE_SEMANTICS,
        score_threshold=0.72,
        margin_threshold=0.08,
        rights_attestation_path=producer_root
        / "tests/fixtures/mobile-catalog/rights-attestation.json",
    )
    producer.write_mobile_catalog(output, embeddings, rows, release)
    artifacts = {
        name: _sha256(output / name)
        for name in ("manifest.json", "metadata.json", "references.f16")
    }
    provenance = {
        "producerCommit": PRODUCER_COMMIT,
        "generator": "FixtureGeneration/generate_python_catalog.py",
        "command": ".venv/bin/python <generator> --producer-root . --output <python-catalog>",
        "inputs": {
            "dimension": DIMENSION,
            "scoreInputs": [list(item) for item in SCORE_INPUTS],
            "rightsFixture": "tests/fixtures/mobile-catalog/rights-attestation.json",
        },
        "artifacts": artifacts,
        "golden": _golden(output),
    }
    provenance_path = output.parent / "python-catalog-provenance.json"
    provenance_path.write_text(
        json.dumps(provenance, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
