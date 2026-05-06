#!/usr/bin/env python3
import json
import shutil
import subprocess
import sys


def command_works(command: str) -> bool:
    path = shutil.which(command)
    if path is None:
        return False

    try:
        subprocess.run(
            [path, "-version"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=True,
        )
        return True
    except (OSError, subprocess.CalledProcessError):
        return False


def main() -> int:
    result = {
        "python": sys.version,
        "pythonExecutable": sys.executable,
        "ffmpeg": shutil.which("ffmpeg"),
        "ffmpegWorks": command_works("ffmpeg"),
        "ffprobe": shutil.which("ffprobe"),
        "ffprobeWorks": command_works("ffprobe"),
    }

    failures: list[str] = []

    if sys.version_info[:2] != (3, 12):
        failures.append("Python 3.12 is required.")

    try:
        import torch

        result["torch"] = torch.__version__
        result["mpsAvailable"] = bool(
            hasattr(torch.backends, "mps") and torch.backends.mps.is_available()
        )
    except Exception as exc:
        failures.append(f"Could not import torch: {exc}")

    try:
        import transkun

        result["transkun"] = transkun.__file__
    except Exception as exc:
        failures.append(f"Could not import transkun: {exc}")

    try:
        import imageio_ffmpeg

        result["imageioFfmpeg"] = imageio_ffmpeg.get_ffmpeg_exe()
    except Exception as exc:
        result["imageioFfmpeg"] = None
        failures.append(f"Could not resolve imageio-ffmpeg fallback: {exc}")

    result["ok"] = not failures
    result["failures"] = failures

    print(json.dumps(result, indent=2, sort_keys=True))

    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
