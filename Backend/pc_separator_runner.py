#!/usr/bin/env python3
import argparse
import json
import os
import sys
from pathlib import Path


def emit(event: str, **payload):
    print(json.dumps({"event": event, **payload}), flush=True)


def fail(message: str) -> int:
    emit("error", message=message)
    return 1


def validate_repo(repo: Path) -> list[str]:
    failures: list[str] = []

    if not (repo / "utils.py").exists():
        failures.append(f"Missing pc-separation utils.py in {repo}")

    if not (repo / "config").is_dir():
        failures.append(f"Missing pc-separation config directory in {repo}")

    checkpoint_dir = repo / "checkpoints"
    if not checkpoint_dir.is_dir():
        failures.append(
            f"Missing pretrained checkpoints in {checkpoint_dir}. "
            "Run Packaging/build_pc_separation_dev.sh --download-weights."
        )
    else:
        hdmc_best = checkpoint_dir / "HDMC20_R_H_HU_HUS" / "hdemucs_best.pth"
        if not hdmc_best.exists():
            failures.append(
                f"Missing HDMC pretrained checkpoint: {hdmc_best}. "
                "Run Packaging/build_pc_separation_release.sh."
            )

    return failures


def doctor(repo: Path) -> int:
    result = {
        "python": sys.version,
        "pythonExecutable": sys.executable,
        "repo": str(repo),
        "ok": True,
        "failures": [],
    }

    failures = validate_repo(repo)

    try:
        import torch

        result["torch"] = torch.__version__
    except Exception as exc:
        failures.append(f"Could not import torch: {exc}")

    try:
        import torchaudio

        result["torchaudio"] = torchaudio.__version__
    except Exception as exc:
        failures.append(f"Could not import torchaudio: {exc}")

    try:
        import soundfile

        result["soundfile"] = getattr(soundfile, "__version__", "available")
    except Exception as exc:
        failures.append(f"Could not import soundfile: {exc}")

    try:
        import pydub

        result["pydub"] = getattr(pydub, "__version__", "available")
    except Exception as exc:
        failures.append(f"Could not import pydub: {exc}")

    try:
        import yaml

        result["yaml"] = getattr(yaml, "__version__", "available")
    except Exception as exc:
        failures.append(f"Could not import yaml: {exc}")

    result["failures"] = failures
    result["ok"] = not failures
    print(json.dumps(result, indent=2, sort_keys=True), flush=True)

    return 0 if not failures else 1


def normalize_audio(audio, sample_rate: int, target_rate: int, channels: int):
    import torch
    import torchaudio

    if sample_rate != target_rate:
        audio = torchaudio.functional.resample(audio, sample_rate, target_rate)

    if audio.shape[0] == channels:
        return audio

    if channels == 2 and audio.shape[0] == 1:
        return audio.repeat(2, 1)

    if channels == 1 and audio.shape[0] > 1:
        return audio.mean(dim=0, keepdim=True)

    if audio.shape[0] > channels:
        return audio[:channels, :]

    repeats = int(torch.ceil(torch.tensor(channels / audio.shape[0])).item())
    return audio.repeat(repeats, 1)[:channels, :]


def load_audio(path: Path):
    import numpy as np
    import soundfile as sf
    import torch

    try:
        samples, sample_rate = sf.read(str(path), always_2d=True, dtype="float32")
    except Exception:
        from pydub import AudioSegment

        segment = AudioSegment.from_file(str(path))
        raw = np.array(segment.get_array_of_samples())
        if segment.channels > 1:
            samples = raw.reshape((-1, segment.channels))
        else:
            samples = raw.reshape((-1, 1))

        scale = float(1 << (8 * segment.sample_width - 1))
        samples = samples.astype(np.float32) / scale
        sample_rate = segment.frame_rate

    audio = torch.from_numpy(np.ascontiguousarray(samples.T))
    return audio, int(sample_rate)


def save_audio(path: Path, audio, sample_rate: int):
    import numpy as np
    import soundfile as sf

    samples = audio.detach().cpu().float().clamp(-1.0, 1.0).numpy().T
    sf.write(str(path), np.ascontiguousarray(samples), sample_rate)


def cfg_value(root, dotted_key: str, default):
    value = root
    for key in dotted_key.split("."):
        value = getattr(value, key, None)
        if value is None:
            return default
    return value


def separate(
    input_path: Path,
    output_path: Path,
    repo: Path,
    model: str,
    device: str,
    split: bool,
    overlap: float | None,
    shifts: int | None,
) -> int:
    failures = validate_repo(repo)
    if failures:
        return fail("; ".join(failures))

    sys.path.insert(0, str(repo))
    os.chdir(repo)

    import torch
    from model.demucs.apply import apply_model, apply_model_hpss
    from utils import init_separator

    original_torch_load = torch.load

    def compatible_torch_load(*args, **kwargs):
        kwargs.setdefault("weights_only", False)
        return original_torch_load(*args, **kwargs)

    torch.load = compatible_torch_load
    torch.set_grad_enabled(False)

    emit("loading_separator", model=model, device=device)
    separator = init_separator(model_type=model, device=device)

    sample_rate = int(getattr(separator, "_sample_rate", 44100))
    channels = int(getattr(separator, "_num_channels", 2))
    targets = list(getattr(separator, "_targets", ["piano", "orch"]))
    model_cfg = getattr(separator, "_model_cfg", None)
    model_split = bool(split if split is not None else cfg_value(model_cfg, "test.split", True))
    model_overlap = float(overlap if overlap is not None else cfg_value(model_cfg, "test.overlap", 0.25))
    model_shifts = int(shifts if shifts is not None else cfg_value(model_cfg, "test.shifts", 1))

    emit("reading_audio", input=str(input_path))
    audio, source_rate = load_audio(input_path)
    audio = normalize_audio(audio, source_rate, sample_rate, channels)
    audio = audio.to(device)

    duration = audio.shape[-1] / sample_rate
    emit(
        "separating",
        split=model_split,
        overlap=model_overlap,
        shifts=model_shifts,
        durationSeconds=round(duration, 2),
    )
    with torch.no_grad():
        mix = audio.unsqueeze(0)
        if hasattr(separator, "_model"):
            if getattr(separator._model, "_hpss_output", False):
                estimates_tensor = apply_model_hpss(
                    separator._model,
                    mix,
                    split=model_split,
                    overlap=model_overlap,
                    shifts=model_shifts,
                    num_workers=0,
                    device=device,
                )[0]
            else:
                estimates_tensor = apply_model(
                    separator._model,
                    mix,
                    split=model_split,
                    overlap=model_overlap,
                    shifts=model_shifts,
                    num_workers=0,
                    device=device,
                )
            estimates = {
                target: estimates_tensor[:, target_idx, ...].squeeze(0)
                for target_idx, target in enumerate(targets)
            }
        else:
            estimates = separator.separate(mix)

    if "piano" not in estimates:
        return fail("pc-separation did not return a piano estimate.")

    piano = estimates["piano"].detach().cpu()
    if piano.ndim == 3:
        piano = piano.squeeze(0)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    emit("writing_piano_stem", output=str(output_path))
    save_audio(output_path, piano, sample_rate)
    emit("done", output=str(output_path))

    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Piano transcribe pc-separation runner")
    parser.add_argument("--input", help="Input concerto audio file")
    parser.add_argument("--output", help="Output piano stem WAV")
    parser.add_argument("--repo", default=os.environ.get("PIANO_TRANSCRIBE_PC_SEPARATION_ROOT"))
    parser.add_argument("--model", default="HDMC", choices=["UMX06", "UMX20", "SPL", "DMC", "HDMC"])
    parser.add_argument("--device", default="cpu", choices=["cpu", "cuda"])
    parser.add_argument("--no-split", action="store_true", help="Disable chunked model application.")
    parser.add_argument("--overlap", type=float, default=None, help="Chunk overlap ratio for split separation.")
    parser.add_argument("--shifts", type=int, default=None, help="Number of test-time shifts.")
    parser.add_argument("--doctor", action="store_true")

    args = parser.parse_args()

    if not args.repo:
        return fail("Missing --repo or PIANO_TRANSCRIBE_PC_SEPARATION_ROOT.")

    repo = Path(args.repo).resolve()

    if args.doctor:
        return doctor(repo)

    if not args.input or not args.output:
        return fail("--input and --output are required unless --doctor is used.")

    try:
        return separate(
            input_path=Path(args.input).resolve(),
            output_path=Path(args.output).resolve(),
            repo=repo,
            model=args.model,
            device=args.device,
            split=not args.no_split,
            overlap=args.overlap,
            shifts=args.shifts,
        )
    except Exception as exc:
        emit("error", message=str(exc))
        raise


if __name__ == "__main__":
    raise SystemExit(main())
