#!/usr/bin/env python3
"""Generate the deterministic Swift preprocessing and Core ML parity fixtures."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys
import tempfile

import coremltools as ct
import numpy as np
from PIL import Image


MODEL_COMMIT = "7aa6474ca51c4c7e91cd4552093e7cc3424924b2"
MODEL_PACKAGE_SHA256 = "e784dac753edb2b70dd31d1a74208b736cf805c0e34b87d81a7bad11e1c13109"
PINNED_PILLOW_VERSION = "12.3.0"
MEAN = np.asarray([0.485, 0.456, 0.406], dtype=np.float32)
STD = np.asarray([0.229, 0.224, 0.225], dtype=np.float32)
PACKAGE_HASH_DOMAIN = b"fluke-coreml-package-v1\0"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def package_tree_digest(package: Path) -> str:
    if package.is_symlink() or not package.is_dir():
        raise RuntimeError("model package must be a regular directory")
    entries = sorted(package.rglob("*"), key=lambda path: path.relative_to(package).as_posix())
    if not entries:
        raise RuntimeError("model package must not be empty")
    result = hashlib.sha256(PACKAGE_HASH_DOMAIN)
    for path in entries:
        if path.is_symlink():
            raise RuntimeError(f"model package contains a symbolic link: {path}")
        relative = path.relative_to(package).as_posix().encode("utf-8")
        if not path.is_dir() and not path.is_file():
            raise RuntimeError(f"model package contains a non-regular entry: {path}")
        kind = b"D" if path.is_dir() else b"F"
        result.update(kind)
        result.update(len(relative).to_bytes(8, byteorder="big"))
        result.update(relative)
        if path.is_file():
            result.update(path.read_bytes())
    return result.hexdigest()


def source_pixels(width: int = 311, height: int = 173) -> np.ndarray:
    y, x = np.indices((height, width), dtype=np.uint32)
    red = (x * 17 + y * 29 + ((x // 11) ^ (y // 7)) * 31) % 256
    green = (x * x + y * 13 + (x * y) // 5) % 256
    blue = ((x ^ (y * 3)) * 19 + (x // 3) * 7 + y * y) % 256
    return np.stack((red, green, blue), axis=-1).astype(np.uint8)


def preprocess(source: Image.Image) -> np.ndarray:
    oriented = source.transpose(Image.Transpose.ROTATE_270)
    width, height = oriented.size
    if width <= height:
        target = (256, int(256 * height / width))
    else:
        target = (int(256 * width / height), 256)
    resized = oriented.resize(target, resample=Image.Resampling.BICUBIC)
    left = (target[0] - 224) // 2
    top = (target[1] - 224) // 2
    cropped = np.asarray(resized.crop((left, top, left + 224, top + 224)), dtype=np.uint8)
    normalized = (cropped.astype(np.float32) / np.float32(255.0) - MEAN) / STD
    return np.ascontiguousarray(normalized.transpose(2, 0, 1)[None, ...], dtype="<f4")


def write_floats(path: Path, values: np.ndarray) -> None:
    path.write_bytes(np.ascontiguousarray(values, dtype="<f4").tobytes())


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-package", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if Image.__version__ != PINNED_PILLOW_VERSION:
        raise RuntimeError(
            f"Pillow {PINNED_PILLOW_VERSION} is required; found {Image.__version__}"
        )
    actual_package_digest = package_tree_digest(args.model_package)
    if actual_package_digest != MODEL_PACKAGE_SHA256:
        raise RuntimeError(
            f"unexpected model package digest: {actual_package_digest}"
        )
    args.output.mkdir(parents=True, exist_ok=True)

    source_path = args.output / "preprocessing-source.png"
    tensor_path = args.output / "preprocessing-golden.f32"
    embedding_path = args.output / "embedding-golden.f32"
    provenance_path = args.output / "preprocessing-provenance.json"

    source = Image.fromarray(source_pixels(), mode="RGB")
    source.save(source_path, format="PNG", optimize=False)
    tensor = preprocess(source)
    write_floats(tensor_path, tensor)

    with tempfile.TemporaryDirectory() as temporary_directory:
        copied_package = Path(temporary_directory) / "FlukeEmbedder.mlpackage"
        shutil.copytree(args.model_package.resolve(), copied_package)
        prediction = ct.models.MLModel(str(copied_package)).predict({"pixels": tensor})
    embedding = np.asarray(prediction["embedding"], dtype=np.float32).reshape(1, 384)
    write_floats(embedding_path, embedding)

    provenance = {
        "schemaVersion": 1,
        "producerCommit": MODEL_COMMIT,
        "generatorSHA256": digest(Path(__file__)),
        "modelPackageSHA256": MODEL_PACKAGE_SHA256,
        "pillowVersion": Image.__version__,
        "pythonVersion": sys.version.split()[0],
        "numpyVersion": np.__version__,
        "coremltoolsVersion": ct.__version__,
        "orientation": {"cgImagePropertyOrientation": 6, "name": "right"},
        "source": {
            "width": 311,
            "height": 173,
            "colorSpace": "sRGB",
            "kind": "deterministic synthetic pattern",
            "rights": "generated for this test suite; no third-party content",
        },
        "preprocessing": {
            "version": "dinov2-imagenet-v1",
            "resizeShortestEdge": 256,
            "resample": "Pillow BICUBIC",
            "centerCrop": [224, 224],
            "mean": MEAN.tolist(),
            "standardDeviation": STD.tolist(),
        },
        "tensor": {"shape": [1, 3, 224, 224], "dtype": "little-endian-float32"},
        "embedding": {"shape": [1, 384], "dtype": "little-endian-float32"},
        "artifacts": {
            source_path.name: digest(source_path),
            tensor_path.name: digest(tensor_path),
            embedding_path.name: digest(embedding_path),
        },
    }
    provenance_path.write_text(json.dumps(provenance, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
