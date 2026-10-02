#!/usr/bin/env python3
"""Validate the staged offline runtime, model assets, decoders, and notice inventory."""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def main() -> None:
    root = Path(sys.argv[1]).resolve()
    if sys.version_info[:2] != (3, 12) or not Path(sys.executable).resolve().is_relative_to(root / "python"):
        raise SystemExit("Verification must use the staged Python 3.12 runtime.")
    required = ["transkun_runner.py", "checkpoints.json", "bin/ffmpeg", "bin/ffprobe",
                "licenses/PYTHON-PACKAGES.json", "licenses/python/PYTHON.json",
                "licenses/ffmpeg/COPYING.LGPLv2.1", "licenses/ffmpeg/BUILD-CONFIGURATION.txt"]
    for relative in required:
        if not (root / relative).is_file():
            raise SystemExit(f"Required backend asset missing: {relative}")
    for name in ("torch", "transkun", "moduleconf", "numpy", "soxr"):
        if importlib.util.find_spec(name) is None:
            raise SystemExit(f"Required package missing: {name}")
    import torch
    import transkun
    print(f"Python {sys.version.split()[0]}, torch {torch.__version__}")
    manifests = json.loads((root / "checkpoints.json").read_text())
    package = Path(transkun.__file__).resolve().parent / "pretrained"
    for identifier, directory in (("packaged-default", package),
                                  ("benchmark-v2", root / "transkun-checkpoints/benchmark-v2")):
        if identifier == "benchmark-v2" and not directory.exists():
            continue
        item = manifests[identifier]
        for kind in ("weight", "config"):
            path = directory / item[kind]
            if digest(path) != item[kind + "SHA256"]:
                raise SystemExit(f"Model checksum mismatch: {identifier}/{kind}")
    for name in ("ffmpeg", "ffprobe"):
        result = subprocess.run([str(root / "bin" / name), "-version"], check=True,
                                capture_output=True, text=True)
        if any(flag in result.stdout for flag in ("--enable-gpl", "--enable-nonfree", "--enable-version3")):
            raise SystemExit(f"Unsupported GPL/nonfree build: {name}")
    print("Offline backend assets verified.")


if __name__ == "__main__":
    main()
