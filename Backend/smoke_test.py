from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import wave


def write_silent_wav(path: Path):
    with wave.open(str(path), "w") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(44100)
        for _ in range(44100):
            wav.writeframes(struct.pack("<h", 0))


def main():
    import torch
    import transkun

    print("Python:", sys.version)
    print("Torch:", torch.__version__)
    print("Transkun:", transkun.__file__)

    with tempfile.TemporaryDirectory() as tmp_dir:
        tmp = Path(tmp_dir)
        wav = tmp / "silence.wav"
        mid = tmp / "out.mid"

        write_silent_wav(wav)

        cmd = [
            sys.executable,
            "Backend/transkun_runner.py",
            "--input",
            str(wav),
            "--output",
            str(mid),
            "--device",
            "cpu",
        ]
        subprocess.run(cmd, check=True)

        if not mid.exists() or mid.stat().st_size == 0:
            raise RuntimeError("Smoke test did not produce a MIDI file.")

        print("Smoke test OK:", mid)


if __name__ == "__main__":
    main()
