#!/usr/bin/env python3
import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

import moduleconf
import numpy as np
import torch
from pydub import AudioSegment

import transkun
from transkun.Data import writeMidi


def emit(event: str, **payload):
    print(json.dumps({"event": event, **payload}), flush=True)


def package_file(relative: str) -> Path:
    root = Path(transkun.__file__).resolve().parent
    return root / relative


def read_audio(path: Path):
    if not path.exists():
        raise FileNotFoundError(f"Input audio file does not exist: {path}")

    configure_ffmpeg()

    try:
        audio = AudioSegment.from_file(str(path))
    except FileNotFoundError as exc:
        if path.suffix.lower() != ".wav" and shutil.which("ffmpeg") is None:
            raise RuntimeError(
                "ffmpeg was not found. Compressed audio formats require ffmpeg "
                "or a bundled release backend."
            ) from exc
        raise

    samples = np.array(audio.get_array_of_samples())

    if audio.channels > 1:
        samples = samples.reshape((-1, audio.channels))
    else:
        samples = samples.reshape((-1, 1))

    # Transkun's original path assumes 16-bit audio and divides by 2**15.
    # This generalizes the scaling to the decoded sample width.
    scale = float(1 << (8 * audio.sample_width - 1))
    samples = samples.astype(np.float32) / scale

    return audio.frame_rate, samples


def configure_ffmpeg():
    system_ffmpeg = shutil.which("ffmpeg")
    if system_ffmpeg is None or not binary_works(system_ffmpeg):
        try:
            import imageio_ffmpeg
        except ImportError:
            if system_ffmpeg is not None:
                emit("warning", message=f"ffmpeg exists but could not run: {system_ffmpeg}")
        else:
            bundled_ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
            AudioSegment.converter = bundled_ffmpeg
            emit("using_ffmpeg", path=bundled_ffmpeg)

    configure_ffprobe()


def configure_ffprobe():
    system_ffprobe = shutil.which("ffprobe")
    if system_ffprobe is not None and binary_works(system_ffprobe):
        return

    import pydub.audio_segment as audio_segment

    audio_segment.mediainfo_json = lambda *args, **kwargs: None
    if system_ffprobe is not None:
        emit(
            "warning",
            message=f"ffprobe exists but could not run: {system_ffprobe}; decoding without probe.",
        )


def binary_works(path: str) -> bool:
    try:
        subprocess.run(
            [path, "-version"],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return True
    except (OSError, subprocess.CalledProcessError):
        return False


def resolve_device(requested: str) -> str:
    if requested == "mps":
        if hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
            return "mps"
        emit("warning", message="MPS requested but unavailable; falling back to CPU.")
    return "cpu"


def load_checkpoint(weight_path: Path, device: str):
    try:
        return torch.load(str(weight_path), map_location=device, weights_only=False)
    except TypeError:
        return torch.load(str(weight_path), map_location=device)


def transcribe(
    input_path: Path,
    output_path: Path,
    device: str,
    segment_hop_size: float | None,
    segment_size: float | None,
):
    emit("loading_config")

    weight_path = package_file("pretrained/2.0.pt")
    conf_path = package_file("pretrained/2.0.conf")

    if not weight_path.exists():
        raise FileNotFoundError(f"Missing Transkun weight file: {weight_path}")
    if not conf_path.exists():
        raise FileNotFoundError(f"Missing Transkun config file: {conf_path}")

    conf_manager = moduleconf.parseFromFile(str(conf_path))
    transkun_type = conf_manager["Model"].module.TransKun
    conf = conf_manager["Model"].config

    device = resolve_device(device)

    emit("loading_model", device=device)
    checkpoint = load_checkpoint(weight_path, device)
    model = transkun_type(conf=conf).to(device)

    if "best_state_dict" in checkpoint:
        model.load_state_dict(checkpoint["best_state_dict"], strict=False)
    else:
        model.load_state_dict(checkpoint["state_dict"], strict=False)

    model.eval()
    torch.set_grad_enabled(False)

    emit("reading_audio", input=str(input_path))
    fs, audio = read_audio(input_path)

    if fs != model.fs:
        emit("resampling", source_rate=fs, target_rate=model.fs)
        import soxr

        audio = soxr.resample(audio, fs, model.fs)

    emit("transcribing")
    x = torch.from_numpy(audio).to(device)

    kwargs = {"discardSecondHalf": False}
    if segment_hop_size is not None:
        kwargs["stepInSecond"] = segment_hop_size
    if segment_size is not None:
        kwargs["segmentSizeInSecond"] = segment_size

    notes_est = model.transcribe(x, **kwargs)

    emit("writing_midi", output=str(output_path))
    midi = writeMidi(notes_est)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    midi.write(str(output_path))

    emit("done", output=str(output_path))


def main() -> int:
    parser = argparse.ArgumentParser(description="Piano transcribe backend runner")
    parser.add_argument("--input", required=True, help="Input audio file")
    parser.add_argument("--output", required=True, help="Output MIDI file")
    parser.add_argument("--device", default="cpu", choices=["cpu", "mps"])
    parser.add_argument("--segment-hop-size", type=float, default=None)
    parser.add_argument("--segment-size", type=float, default=None)

    args = parser.parse_args()

    try:
        transcribe(
            input_path=Path(args.input),
            output_path=Path(args.output),
            device=args.device,
            segment_hop_size=args.segment_hop_size,
            segment_size=args.segment_size,
        )
    except Exception as exc:
        emit("error", message=str(exc), type=exc.__class__.__name__)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
