#!/usr/bin/env python3
"""Exercise the native app's automation entrypoint without touching user settings."""

import argparse
import json
import math
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import time
import wave


def write_tone(path):
    rate = 44100
    frames = bytearray()
    for index in range(rate * 2):
        envelope = math.exp(-index / rate * 2.5)
        sample = int(7000 * envelope * math.sin(2 * math.pi * 440 * index / rate))
        frames.extend(struct.pack("<hh", sample, sample))
    with wave.open(str(path), "wb") as audio:
        audio.setnchannels(2)
        audio.setsampwidth(2)
        audio.setframerate(rate)
        audio.writeframes(frames)


def validate_midi(path):
    """Parse MIDI with the packaged mido dependency, not a byte-count assertion."""
    import mido

    midi = mido.MidiFile(str(path))
    assert midi.tracks, f"MIDI has no tracks: {path}"
    assert all(track and track[-1].type == "end_of_track" for track in midi.tracks), path
    return sum(message.type == "note_on" and message.velocity > 0
               for track in midi.tracks for message in track)


def clean_environment():
    return {
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "HOME": str(Path.home()),
        "TMPDIR": tempfile.gettempdir(),
        "LANG": "en_US.UTF-8",
        "PIANO_TRANSCRIBE_TEST_MODE": "1",
        "PIANO_TRANSCRIBE_AUTORUN_REVEAL": "0",
        "PIANO_TRANSCRIBE_AUTORUN_QUIT": "1",
        "PIANO_TRANSCRIBE_AUTORUN_TRANSKUN_CHECKPOINT": "packaged-default",
    }


def run_case(binary, temporary, input_path, case, environment, output_folder=None, checkpoint="packaged-default"):
    result_path = temporary / f"result-{case}.json"
    launch_env = dict(environment)
    launch_env.update({
        "PIANO_TRANSCRIBE_AUTORUN_INPUT": str(input_path),
        "PIANO_TRANSCRIBE_AUTORUN_RESULT_FILE": str(result_path),
        "PIANO_TRANSCRIBE_AUTORUN_OUTPUT_DESTINATION": "custom-folder" if output_folder else "source-folder",
        "PIANO_TRANSCRIBE_AUTORUN_TRANSKUN_CHECKPOINT": checkpoint,
    })
    if output_folder:
        launch_env["PIANO_TRANSCRIBE_AUTORUN_OUTPUT_FOLDER"] = str(output_folder)
    console = temporary / f"console-{case}.log"
    with console.open("wb") as log:
        # Keep the exact PID of this instance; never kill another Piano transcribe.
        process = subprocess.Popen(
            [str(binary), "-ApplePersistenceIgnoreState", "YES", "-NSQuitAlwaysKeepsWindows", "NO"],
            cwd=temporary, env=launch_env, stdout=log, stderr=log)
        try:
            deadline = time.monotonic() + 300
            while time.monotonic() < deadline:
                if result_path.is_file():
                    result = json.loads(result_path.read_text())
                    process.wait(timeout=20)
                    assert process.returncode == 0, console.read_text(errors="replace")
                    return result
                if process.poll() is not None:
                    hint = ""
                    if process.returncode == -6:
                        hint = (" Check the app crash report; if AppKit registration failed, "
                                "run native UI tests outside the restricted shell sandbox.")
                    raise AssertionError(f"App exited before result ({process.returncode}): "
                                         f"{console.read_text(errors='replace')}{hint}")
                time.sleep(0.1)
            raise TimeoutError(f"Timed out waiting for {case}: {console.read_text(errors='replace')}")
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)


def assert_completed(result, expected_folder, checkpoint):
    assert result["status"] == "completed", result
    assert result["checkpoint"] == checkpoint, result
    assert result["outputExists"] is True, result
    output = Path(result["output"])
    assert output.parent == expected_folder, result
    assert output.suffix == ".mid", result
    return output, validate_midi(output)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("app_bundle", type=Path)
    parser.add_argument("--debug-root", type=Path)
    parser.add_argument("--python", type=Path)
    parser.add_argument("--benchmark", action="store_true")
    parser.add_argument("--piano-fixture", type=Path)
    args = parser.parse_args()
    bundle = args.app_bundle.resolve()
    binary = bundle / "Contents/MacOS/Piano transcribe"
    assert binary.is_file(), binary
    environment = clean_environment()
    if args.debug_root:
        assert args.python, "Debug E2E requires an explicit backend interpreter."
        environment["PIANO_TRANSCRIBE_ROOT"] = str(args.debug_root.resolve())
        environment["PIANO_TRANSCRIBE_PYTHON"] = str(args.python.absolute())
        decoder_directory = os.environ.get("PIANO_TRANSCRIBE_FFMPEG_BIN")
        if decoder_directory:
            environment["PIANO_TRANSCRIBE_FFMPEG_BIN"] = decoder_directory
        benchmark = os.environ.get("PIANO_TRANSCRIBE_TRANSKUN_BENCHMARK_DIR")
        if benchmark:
            environment["PIANO_TRANSCRIBE_TRANSKUN_BENCHMARK_DIR"] = benchmark
    with tempfile.TemporaryDirectory(prefix="piano-transcribe-e2e-") as directory:
        temporary = Path(directory)
        source = temporary / "decoder-tone.wav"
        write_tone(source)
        result = run_case(binary, temporary, source, "source", environment)
        output, count = assert_completed(result, temporary, "packaged-default")
        assert output.name == "decoder-tone-transkun.mid", result
        original = output.read_bytes()
        print(f"Native audio -> MIDI passed (audible decoder fixture, {count} notes; not a quality benchmark).")

        collision = run_case(binary, temporary, source, "collision", environment)
        second, _ = assert_completed(collision, temporary, "packaged-default")
        assert second != output and output.read_bytes() == original, collision
        print("Existing MIDI preserved; subsequent export has its own filename.")

        custom = temporary / "custom-output"
        custom.mkdir()
        result = run_case(binary, temporary, source, "custom", environment, output_folder=custom)
        assert_completed(result, custom, "packaged-default")
        print("Custom output folder passed.")

        invalid = temporary / "not-audio.mid"
        invalid.write_bytes(original)
        result = run_case(binary, temporary, invalid, "midi-rejection", environment)
        assert result["status"] == "failed", result
        assert "MIDI files are not valid input" in result["message"], result
        print("MIDI input rejection passed.")

        if args.benchmark or os.environ.get("PIANO_TRANSCRIBE_TEST_BENCHMARK_CHECKPOINT") == "1":
            result = run_case(binary, temporary, source, "benchmark", environment, checkpoint="benchmark-v2")
            assert_completed(result, temporary, "benchmark-v2")
            print("Optional benchmark checkpoint passed.")

        fixture = args.piano_fixture or os.environ.get("PIANO_TRANSCRIBE_PIANO_FIXTURE")
        if fixture:
            owned_source = Path(fixture).resolve(strict=True)
            destination = temporary / owned_source.name
            shutil.copy2(owned_source, destination)
            result = run_case(binary, temporary, destination, "owned-piano", environment)
            _, count = assert_completed(result, temporary, "packaged-default")
            assert count > 0, "The supplied piano fixture produced no notes."
            print(f"Supplied piano recording passed: {count} note-on events (no reference-accuracy score claimed).")


if __name__ == "__main__":
    main()
