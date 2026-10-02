#!/usr/bin/env python3
"""Offline Transkun adapter. Stdout is protocol v1 NDJSON; diagnostics use stderr."""

import argparse
from collections import defaultdict
import contextlib
from dataclasses import dataclass
import hashlib
import importlib.metadata
import json
import math
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import traceback

PROTOCOL_VERSION = 1
PROTOCOL_OUTPUT = sys.stdout
SUPPORTED_EXTENSIONS = {"mp3", "wav", "aif", "aiff", "m4a", "flac"}
PACKAGED_DEFAULT_CHECKPOINT = "packaged-default"
BENCHMARK_V2_CHECKPOINT = "benchmark-v2"
_active_process: subprocess.Popen | None = None


class BackendError(Exception):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code


class RunnerCancelled(Exception):
    pass


def emit(event: str, **payload):
    print(json.dumps({"version": PROTOCOL_VERSION, "event": event, **payload}, allow_nan=False),
          file=PROTOCOL_OUTPUT, flush=True)


def stop_child():
    global _active_process
    process = _active_process
    if process is not None and process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
    _active_process = None


def cancel(_signal, _frame):
    raise RunnerCancelled()


def capture(command: list[str], timeout: float = 30) -> bytes:
    global _active_process
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    _active_process = process
    try:
        stdout, stderr = process.communicate(timeout=timeout)
        if process.returncode != 0:
            print(stderr.decode("utf-8", errors="replace")[-16384:], file=sys.stderr)
            raise BackendError("decoder_failed", "The audio decoder could not read this file.")
        return stdout
    except subprocess.TimeoutExpired as exc:
        raise BackendError("decoder_timeout", "The audio decoder did not respond.") from exc
    finally:
        stop_child()


def resolve_binary(name: str, explicit: str | None) -> Path:
    candidate = Path(explicit) if explicit else Path(__file__).resolve().parent / "bin" / name
    if not candidate.is_absolute():
        raise BackendError("decoder_missing", f"The {name} path must be absolute.")
    if not candidate.is_file() or not os.access(candidate, os.X_OK):
        raise BackendError("decoder_missing", f"The bundled {name} executable is missing.")
    try:
        capture([str(candidate), "-version"])
    except (BackendError, OSError) as exc:
        raise BackendError("decoder_invalid", f"The bundled {name} executable could not launch.") from exc
    return candidate


def validate_input(path: Path):
    suffix = path.suffix.lower().lstrip(".")
    if suffix in {"mid", "midi"}:
        raise BackendError("unsupported_input", "Choose an audio file, not a MIDI file.")
    if suffix == "movpkg":
        raise BackendError("unsupported_input", "Apple Music packages cannot be transcribed. Choose unprotected audio.")
    if suffix not in SUPPORTED_EXTENSIONS:
        raise BackendError("unsupported_input", "This audio format is not supported.")
    if not path.is_file() or path.stat().st_size == 0:
        raise BackendError("invalid_input", "The audio file is missing or empty.")


@dataclass(frozen=True)
class AudioInfo:
    duration: float
    channels: int
    sample_rate: int


def probe_audio(path: Path, ffprobe: Path) -> AudioInfo:
    try:
        info = json.loads(capture([
            str(ffprobe), "-v", "error", "-select_streams", "a:0", "-show_streams",
            "-show_format", "-of", "json", str(path),
        ]))
        stream = info["streams"][0]
        duration = float(stream.get("duration") or info.get("format", {}).get("duration"))
        channels, sample_rate = int(stream["channels"]), int(stream["sample_rate"])
        if not math.isfinite(duration) or duration <= 0 or channels <= 0 or sample_rate <= 0:
            raise ValueError("Invalid audio metadata")
        return AudioInfo(duration=duration, channels=channels, sample_rate=sample_rate)
    except (ValueError, TypeError, KeyError, IndexError) as exc:
        raise BackendError("invalid_input", "The file does not contain readable audio.") from exc


def checkpoint_paths(checkpoint: str, checkpoint_dir: str | None) -> tuple[Path, Path]:
    import transkun

    if checkpoint == PACKAGED_DEFAULT_CHECKPOINT:
        root = Path(transkun.__file__).resolve().parent / "pretrained"
        return root / "2.0.pt", root / "2.0.conf"
    root = Path(checkpoint_dir) if checkpoint_dir else (
        Path(__file__).resolve().parent / "transkun-checkpoints" / BENCHMARK_V2_CHECKPOINT
    )
    return root / "checkpoint.pt", root / "model.conf"


def verify_checkpoint(checkpoint: str, weight: Path, config: Path):
    manifest = json.loads((Path(__file__).resolve().parent / "checkpoints.json").read_text())
    if manifest.get("version") != 1 or checkpoint not in manifest:
        raise BackendError("checkpoint_invalid", "The model manifest is invalid.")
    for path, key in [(weight, "weightSHA256"), (config, "configSHA256")]:
        if not path.is_file():
            raise BackendError("checkpoint_missing", "The selected Transkun model is not installed.")
        with path.open("rb") as handle:
            digest = hashlib.file_digest(handle, "sha256").hexdigest()
        if digest != manifest[checkpoint][key]:
            raise BackendError("checkpoint_invalid", "The selected Transkun model is damaged or unsupported.")


def segment_settings(config, hop: float | None, size: float | None) -> tuple[float, float]:
    hop = float(config.segmentHopSizeInSecond if hop is None else hop)
    size = float(config.segmentSizeInSecond if size is None else size)
    if not (math.isfinite(hop) and math.isfinite(size) and 0 < hop <= size):
        raise BackendError("invalid_configuration", "Segment sizes must satisfy 0 < hop <= size.")
    return hop, size


def resolve_device(torch, requested: str) -> str:
    if requested == "mps":
        if hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
            return "mps"
        emit("warning", message="Metal is unavailable; using CPU.")
    return "cpu"


def load_model(checkpoint: str, checkpoint_dir: str | None, requested_device: str):
    import moduleconf
    import torch

    if importlib.metadata.version("transkun") != "2.0.1":
        raise BackendError("runtime_invalid", "This backend requires Transkun 2.0.1.")
    weight, config_path = checkpoint_paths(checkpoint, checkpoint_dir)
    verify_checkpoint(checkpoint, weight, config_path)
    entry = moduleconf.parseFromFile(str(config_path))["Model"]
    model = entry.module.TransKun(conf=entry.config)
    payload = torch.load(str(weight), map_location="cpu", weights_only=True)
    state = payload.get("best_state_dict", payload.get("state_dict"))
    if not isinstance(state, dict):
        raise BackendError("checkpoint_invalid", "The selected model has no valid parameter state.")
    # Both official pinned checkpoints match every model key; no exceptions are needed.
    model.load_state_dict(state, strict=True)
    device = resolve_device(torch, requested_device)
    model.to(device).eval()
    return model, device


def decode_audio(input_path: Path, output_path: Path, ffmpeg: Path, sample_rate: int, duration: float,
                 channels: int = 2):
    global _active_process
    needed = math.ceil(duration * sample_rate * 2 * 4)
    if shutil.disk_usage(output_path.parent).free < needed + 64 * 1024 * 1024:
        raise BackendError("disk_full", "There is not enough free space to prepare this recording.")
    command = [
        str(ffmpeg), "-nostdin", "-v", "error", "-nostats", "-progress", "pipe:1",
        "-i", str(input_path), "-map", "0:a:0", "-vn", "-sn", "-dn", "-ar", str(sample_rate),
    ]
    # Duplicate mono unchanged; FFmpeg's default center-channel upmix attenuates it.
    if channels == 1:
        command.extend(["-af", "pan=stereo|c0=c0|c1=c0"])
    command.extend(["-ac", "2", "-acodec", "pcm_f32le", "-f", "f32le", "-n", str(output_path)])
    with tempfile.TemporaryFile() as diagnostics:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=diagnostics, text=True)
        _active_process = process
        try:
            assert process.stdout is not None
            for line in process.stdout:
                key, _, value = line.strip().partition("=")
                if key == "out_time_us":
                    emit("progress", stage="decoding", processedSeconds=min(duration, int(value) / 1_000_000),
                         totalSeconds=duration)
            process.wait()
            if process.returncode != 0:
                diagnostics.seek(0)
                print(diagnostics.read().decode("utf-8", errors="replace")[-16384:], file=sys.stderr)
                raise BackendError("decoder_failed", "The audio decoder could not read this recording.")
        finally:
            stop_child()
            if process.stdout is not None:
                process.stdout.close()
    if output_path.stat().st_size == 0 or output_path.stat().st_size % 8:
        raise BackendError("decoder_failed", "The decoder returned incomplete audio samples.")


class DiskAudio:
    """Reads padded channel-first windows without materializing the complete recording."""

    def __init__(self, path: Path):
        import numpy as np

        self.samples = np.memmap(path, mode="r", dtype="<f4").reshape(-1, 2)
        self.frames = self.samples.shape[0]

    def window(self, start: int, length: int):
        import numpy as np

        result = np.zeros((2, length), dtype=np.float32)
        source_start, source_end = max(0, start), min(self.frames, start + length)
        if source_end > source_start:
            data = self.samples[source_start:source_end]
            if not np.isfinite(data).all():
                raise BackendError("invalid_input", "The decoded audio contains invalid samples.")
            destination = source_start - start
            result[:, destination:destination + len(data)] = data.T
        return result

    def close(self):
        self.samples._mmap.close()


def transcribe_windows(model, audio: DiskAudio, device: str, hop: float, size: float):
    """Transkun 2.0.1's loop with identical framing, note merging and overlap resolution.

    Full-track padding/slicing is replaced by disk-backed reads and window device transfer.
    Note decoding and overlap resolution still use upstream implementations.
    """
    import torch
    from transkun.Data import resolveOverlapping
    from transkun.Util import makeFrame

    padding_seconds = size - hop
    padding_frames = math.ceil(padding_seconds * model.fs)
    padded_length = audio.frames + 2 * padding_frames
    step_frames = math.ceil(hop * model.fs / model.hopSize) * model.hopSize
    segment_frames = math.ceil(size * model.fs)
    events_by_type = defaultdict(list)
    start_position = [math.floor(padding_seconds * model.fs / model.hopSize)] * len(model.targetMIDIPitch)
    total = audio.frames / model.fs
    with torch.no_grad():
        for offset in range(0, padded_length, step_frames):
            sample_window = audio.window(offset - padding_frames, segment_frames)
            frames = makeFrame(torch.from_numpy(sample_window).to(device), model.hopSize, model.windowSize)
            decoded, last_positions = model.transcribeFrames(
                frames.unsqueeze(0), forcedStartPos=start_position, velocityCriteron="hamming",
                onsetBound=None, lastFrameIdx=round(segment_frames / model.hopSize),
            )
            start_position = [max(position - int(step_frames / model.hopSize), 0) for position in last_positions]
            begin = offset / model.fs - padding_seconds
            for note in decoded[0]:
                note.start = max(note.start + begin, 0)
                note.end = max(note.end + begin, note.start)
                previous = events_by_type[note.pitch]
                if previous and note.start < previous[-1].end:
                    if note.hasOnset:
                        previous[-1] = note
                    else:
                        previous[-1].hasOffset = note.hasOffset
                        previous[-1].end = max(note.end, previous[-1].end)
                    continue
                if note.hasOnset:
                    previous.append(note)
            emit("progress", stage="transcribing", processedSeconds=min(total, max(0, begin + hop)),
                 totalSeconds=total)
    for notes in events_by_type.values():
        if notes:
            notes[-1].hasOffset = True
    notes = [note for group in events_by_type.values() for note in group if note.hasOffset]
    return resolveOverlapping(notes)


def validate_midi(path: Path) -> int:
    import pretty_midi

    if not path.is_file() or path.stat().st_size < 14:
        raise BackendError("output_invalid", "Transkun did not create a valid MIDI file.")
    try:
        midi = pretty_midi.PrettyMIDI(str(path))
    except Exception as exc:
        raise BackendError("output_invalid", "Transkun did not create a readable MIDI file.") from exc
    count = 0
    for instrument in midi.instruments:
        for note in instrument.notes:
            if not (math.isfinite(note.start) and math.isfinite(note.end) and 0 <= note.start < note.end
                    and 0 <= note.pitch <= 127 and 0 < note.velocity <= 127):
                raise BackendError("output_invalid", "Transkun returned invalid MIDI notes.")
            count += 1
        for control in instrument.control_changes:
            if not (math.isfinite(control.time) and control.time >= 0
                    and 0 <= control.number <= 127 and 0 <= control.value <= 127):
                raise BackendError("output_invalid", "Transkun returned invalid MIDI control changes.")
    return count


def run(args):
    emit("stage", stage="validating")
    input_path, output_path = Path(args.input).resolve(), Path(args.output).resolve()
    validate_input(input_path)
    if output_path.exists():
        raise BackendError("output_exists", "The MIDI destination already exists.")
    ffmpeg, ffprobe = resolve_binary("ffmpeg", args.ffmpeg), resolve_binary("ffprobe", args.ffprobe)
    info = probe_audio(input_path, ffprobe)
    emit("stage", stage="loading_model")
    model, device = load_model(args.checkpoint, args.checkpoint_dir, args.device)
    hop, size = segment_settings(model.conf, args.segment_hop_size, args.segment_size)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".transkun-", dir=output_path.parent) as temporary:
        directory = Path(temporary)
        pcm = directory / "audio.f32"
        emit("stage", stage="decoding", totalSeconds=info.duration)
        decode_audio(input_path, pcm, ffmpeg, model.fs, info.duration, info.channels)
        audio = DiskAudio(pcm)
        try:
            emit("stage", stage="transcribing", totalSeconds=audio.frames / model.fs)
            notes = transcribe_windows(model, audio, device, hop, size)
        finally:
            audio.close()
        emit("stage", stage="writing_midi")
        from transkun.Data import writeMidi

        midi_path = directory / "output.mid"
        writeMidi(notes).write(str(midi_path))
        note_count = validate_midi(midi_path)
        try:
            os.link(midi_path, output_path)
        except FileExistsError as exc:
            raise BackendError("output_exists", "The MIDI destination already exists.") from exc
    if note_count == 0:
        emit("warning", message="No piano notes were detected in this recording.")
    emit("result", output=str(output_path), checkpoint=args.checkpoint, device=device, noteCount=note_count)


class ArgumentParser(argparse.ArgumentParser):
    def error(self, message):
        raise BackendError("invalid_arguments", message)


def parser() -> argparse.ArgumentParser:
    result = ArgumentParser(description="Piano transcribe offline backend")
    result.add_argument("--input", required=True)
    result.add_argument("--output", required=True)
    result.add_argument("--device", default="cpu", choices=["cpu", "mps"])
    result.add_argument("--checkpoint", default=PACKAGED_DEFAULT_CHECKPOINT,
                        choices=[PACKAGED_DEFAULT_CHECKPOINT, BENCHMARK_V2_CHECKPOINT])
    result.add_argument("--checkpoint-dir")
    result.add_argument("--ffmpeg", help="Absolute bundled FFmpeg executable path")
    result.add_argument("--ffprobe", help="Absolute bundled FFprobe executable path")
    result.add_argument("--segment-hop-size", type=float)
    result.add_argument("--segment-size", type=float)
    return result


def main(argv=None) -> int:
    signal.signal(signal.SIGTERM, cancel)
    signal.signal(signal.SIGINT, cancel)
    try:
        args = parser().parse_args(argv)
        if sys.version_info[:2] != (3, 12):
            raise BackendError("runtime_invalid", "The backend requires Python 3.12.")
        with contextlib.redirect_stdout(sys.stderr):
            run(args)
        return 0
    except RunnerCancelled:
        emit("error", code="cancelled", message="Transcription was cancelled.")
        return 130
    except Exception as exc:
        code = exc.code if isinstance(exc, BackendError) else "transcription_failed"
        message = str(exc) if isinstance(exc, BackendError) else "Transcription failed. Open Details for diagnostics."
        emit("error", code=code, message=message)
        traceback.print_exc(file=sys.stderr)
        return 1
    finally:
        stop_child()


if __name__ == "__main__":
    sys.exit(main())
