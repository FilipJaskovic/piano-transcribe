#!/usr/bin/env python3
"""Checks the explicit offline runtime, decoders, and trusted model assets."""

import argparse
import contextlib
import importlib.metadata
import importlib.util
from pathlib import Path
import sys
import traceback

spec = importlib.util.spec_from_file_location("piano_transcribe_runner", Path(__file__).with_name("transkun_runner.py"))
if spec is None or spec.loader is None:
    raise RuntimeError("The backend runner is missing.")
runner = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = runner
spec.loader.exec_module(runner)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ffmpeg")
    parser.add_argument("--ffprobe")
    parser.add_argument("--checkpoint", default="packaged-default", choices=["packaged-default", "benchmark-v2"])
    parser.add_argument("--checkpoint-dir")
    args = parser.parse_args()
    try:
        if sys.version_info[:2] != (3, 12):
            raise runner.BackendError("runtime_invalid", "Python 3.12 is required.")
        with contextlib.redirect_stdout(sys.stderr):
            ffmpeg = runner.resolve_binary("ffmpeg", args.ffmpeg)
            ffprobe = runner.resolve_binary("ffprobe", args.ffprobe)
            _, device = runner.load_model(args.checkpoint, args.checkpoint_dir, "cpu")
        runner.emit("result", python=sys.version, pythonExecutable=sys.executable,
             torch=importlib.metadata.version("torch"), transkun=importlib.metadata.version("transkun"),
             ffmpeg=str(ffmpeg), ffprobe=str(ffprobe), checkpoint=args.checkpoint, device=device, ok=True)
        return 0
    except Exception as exc:
        runner.emit("error", code=exc.code if isinstance(exc, runner.BackendError) else "runtime_invalid",
             message=str(exc), ok=False)
        traceback.print_exc(file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
