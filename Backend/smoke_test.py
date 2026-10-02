#!/usr/bin/env python3
"""Runs an owned synthetic phrase (or supplied recording); this is not a quality benchmark."""

import argparse
import importlib.util
import json
import math
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import wave

spec = importlib.util.spec_from_file_location("piano_transcribe_runner", Path(__file__).with_name("transkun_runner.py"))
if spec is None or spec.loader is None:
    raise RuntimeError("The backend runner is missing.")
runner = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = runner
spec.loader.exec_module(runner)


def write_phrase(path: Path):
    rate = 44100
    samples = bytearray()
    for index in range(rate * 3):
        time = index / rate
        frequency = [261.6256, 329.6276, 391.9954, 440.0][min(3, int(time / 0.7))]
        age = time % 0.7
        envelope = min(1, age / 0.01) * math.exp(-age * 4)
        sample = sum(math.sin(2 * math.pi * frequency * harmonic * time) / harmonic
                     for harmonic in range(1, 7)) * envelope * 0.25
        value = max(-32768, min(32767, round(sample * 32767)))
        samples.extend(struct.pack("<hh", value, value))
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(2)
        wav.setsampwidth(2)
        wav.setframerate(rate)
        wav.writeframes(samples)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", help="Optional owned piano recording for a meaningful quality review")
    parser.add_argument("--checkpoint", default="packaged-default", choices=["packaged-default", "benchmark-v2"])
    parser.add_argument("--checkpoint-dir")
    parser.add_argument("--ffmpeg")
    parser.add_argument("--ffprobe")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        source = Path(args.input).resolve() if args.input else root / "phrase.wav"
        if not args.input:
            write_phrase(source)
        output = root / "phrase.mid"
        command = [sys.executable, "-I", "-B", str(Path(__file__).with_name("transkun_runner.py")),
                   "--input", str(source), "--output", str(output), "--device", "cpu",
                   "--checkpoint", args.checkpoint]
        for flag, value in [("--checkpoint-dir", args.checkpoint_dir), ("--ffmpeg", args.ffmpeg),
                            ("--ffprobe", args.ffprobe)]:
            if value:
                command.extend([flag, value])
        completed = subprocess.run(command, capture_output=True, text=True, timeout=600)
        print(completed.stdout, end="")
        print(completed.stderr, end="", file=sys.stderr)
        completed.check_returncode()
        events = [json.loads(line) for line in completed.stdout.splitlines()]
        if not events or any(event.get("version") != 1 for event in events) or events[-1]["event"] != "result":
            raise RuntimeError("Runner did not return the expected protocol result.")
        count = runner.validate_midi(output)
        if count == 0:
            raise RuntimeError("No notes were detected in the smoke-test phrase.")
        if events[-1]["noteCount"] != count:
            raise RuntimeError("MIDI contents do not match the result metadata.")
        print(f"Smoke test passed: {count} valid notes. No accuracy claim is made by this synthetic fixture.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
