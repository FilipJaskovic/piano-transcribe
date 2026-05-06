#!/usr/bin/env python3
from pathlib import Path
import os
import struct
import subprocess
import sys
import tempfile
import wave


def write_silent_wav(path: Path, seconds: int = 1):
    with wave.open(str(path), "w") as wav:
        wav.setnchannels(2)
        wav.setsampwidth(2)
        wav.setframerate(44100)
        for _ in range(44100 * seconds):
            wav.writeframes(struct.pack("<hh", 0, 0))


def main() -> int:
    repo = Path(
        os.environ.get(
            "PIANO_TRANSCRIBE_PC_SEPARATION_ROOT",
            "External/pc-separation",
        )
    ).resolve()

    print("Python:", sys.version)
    print("Executable:", sys.executable)
    print("pc-separation repo:", repo)

    with tempfile.TemporaryDirectory() as tmp_dir:
        tmp = Path(tmp_dir)
        wav = tmp / "silence.wav"
        out = tmp / "piano-separated.wav"

        write_silent_wav(wav)

        cmd = [
            sys.executable,
            "Backend/pc_separator_runner.py",
            "--input",
            str(wav),
            "--output",
            str(out),
            "--repo",
            str(repo),
            "--model",
            "HDMC",
            "--device",
            "cpu",
        ]
        subprocess.run(cmd, check=True)

        if not out.exists() or out.stat().st_size == 0:
            raise RuntimeError("pc-separation smoke test did not produce a WAV file.")

        print("pc-separation smoke test OK:", out)
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
