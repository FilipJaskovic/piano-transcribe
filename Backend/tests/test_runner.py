import contextlib
import io
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import wave

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import transkun_runner as runner


class ConfigurationTests(unittest.TestCase):
    def test_each_segment_option_gets_the_other_config_default(self):
        config = SimpleNamespace(segmentHopSizeInSecond=8, segmentSizeInSecond=16)
        self.assertEqual(runner.segment_settings(config, 4, None), (4, 16))
        self.assertEqual(runner.segment_settings(config, None, 24), (8, 24))
        for hop, size in [(0, 16), (17, 16), (math.nan, 16), (8, math.inf)]:
            with self.assertRaises(runner.BackendError):
                runner.segment_settings(config, hop, size)

    def test_midi_rejected_before_importing_models(self):
        with self.assertRaises(runner.BackendError) as error:
            runner.validate_input(Path("example.mid"))
        self.assertEqual(error.exception.code, "unsupported_input")

    def test_decoder_never_searches_path(self):
        with patch.dict(os.environ, {"PATH": "/opt/homebrew/bin"}):
            with self.assertRaises(runner.BackendError):
                runner.resolve_binary("not-bundled", None)
            with self.assertRaises(runner.BackendError):
                runner.resolve_binary("ffmpeg", "ffmpeg")

    def test_changed_model_is_rejected_before_deserialization(self):
        with tempfile.TemporaryDirectory() as directory:
            weight = Path(directory) / "checkpoint.pt"
            config = Path(directory) / "model.conf"
            weight.write_bytes(b"not a trusted checkpoint")
            config.write_text("not a trusted configuration")
            with self.assertRaises(runner.BackendError) as error:
                runner.verify_checkpoint("benchmark-v2", weight, config)
            self.assertEqual(error.exception.code, "checkpoint_invalid")

    def test_protocol_is_versioned_and_cannot_emit_nan(self):
        output = io.StringIO()
        with patch.object(runner, "PROTOCOL_OUTPUT", output):
            runner.emit("progress", stage="transcribing", processedSeconds=1, totalSeconds=2)
            self.assertEqual(json.loads(output.getvalue()), {
                "version": 1, "event": "progress", "stage": "transcribing",
                "processedSeconds": 1, "totalSeconds": 2,
            })
            with self.assertRaises(ValueError):
                runner.emit("progress", processedSeconds=math.nan)

    def test_argument_errors_return_json_without_dependencies(self):
        output = subprocess.run([sys.executable, "-B", str(Path(runner.__file__)), "--input", "x.mid"],
                                capture_output=True, text=True, check=False)
        self.assertEqual(output.returncode, 1)
        event = json.loads(output.stdout)
        self.assertEqual(event["event"], "error")
        self.assertEqual(event["code"], "invalid_arguments")
        self.assertIn("Traceback", output.stderr)

    def test_unavailable_mps_reports_actual_cpu(self):
        output = io.StringIO()
        torch = SimpleNamespace(backends=SimpleNamespace(mps=SimpleNamespace(is_available=lambda: False)))
        with patch.object(runner, "PROTOCOL_OUTPUT", output):
            self.assertEqual(runner.resolve_device(torch, "mps"), "cpu")
        self.assertEqual(json.loads(output.getvalue())["event"], "warning")


class WindowTests(unittest.TestCase):
    def test_disk_windows_preserve_padding_and_frame_merging(self):
        import numpy as np
        import torch
        from transkun.ModelTransformer import TransKun

        class Model:
            fs, hopSize, windowSize = 16, 2, 4
            targetMIDIPitch = [60, 61]
            segmentHopSizeInSecond, segmentSizeInSecond = 0.5, 1

            def __init__(self):
                self.calls = []

            def transcribeFrames(self, frames, **kwargs):
                index = len(self.calls)
                self.calls.append((frames.clone(), kwargs))
                note = SimpleNamespace(pitch=60, start=0.1 if index == 0 else 0,
                                       end=0.8, velocity=70, hasOnset=index == 0,
                                       hasOffset=index >= 2)
                return [[note]], [5, 6]

        samples = np.arange(32, dtype=np.float32).reshape(-1, 2) / 64
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "audio.f32"
            samples.astype("<f4").tofile(path)
            disk = runner.DiskAudio(path)
            try:
                upstream, adapted = Model(), Model()
                expected = TransKun.transcribe(upstream, torch.from_numpy(samples),
                                               stepInSecond=0.5, segmentSizeInSecond=1)
                with patch.object(runner, "PROTOCOL_OUTPUT", io.StringIO()):
                    actual = runner.transcribe_windows(adapted, disk, "cpu", 0.5, 1)
                self.assertEqual([vars(note) for note in expected], [vars(note) for note in actual])
                self.assertEqual(len(upstream.calls), len(adapted.calls))
                for (old_frames, old_kwargs), (new_frames, new_kwargs) in zip(upstream.calls, adapted.calls):
                    self.assertTrue(torch.equal(old_frames, new_frames))
                    self.assertEqual(old_kwargs, new_kwargs)
            finally:
                disk.close()


class DecoderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        ffmpeg = os.environ.get("PIANO_TRANSCRIBE_TEST_FFMPEG")
        ffprobe = os.environ.get("PIANO_TRANSCRIBE_TEST_FFPROBE")
        if not ffmpeg or not ffprobe:
            raise unittest.SkipTest("Set absolute PIANO_TRANSCRIBE_TEST_FFMPEG and ...FFPROBE to test decoding.")
        cls.ffmpeg = runner.resolve_binary("ffmpeg", ffmpeg)
        cls.ffprobe = runner.resolve_binary("ffprobe", ffprobe)
        cls.encoder = runner.resolve_binary("ffmpeg", os.environ.get("PIANO_TRANSCRIBE_TEST_ENCODER", ffmpeg))

    def test_clean_path_formats_preserve_duration_and_finite_float_samples(self):
        import numpy as np

        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"PATH": "/usr/bin:/bin"}):
            root = Path(directory)
            source = root / "tone.wav"
            rate = 48000
            values = (np.sin(np.arange(rate // 5) * (2 * math.pi * 440 / rate)) * 12000).astype("<i2")
            with wave.open(str(source), "wb") as wav:
                wav.setnchannels(1)
                wav.setsampwidth(2)
                wav.setframerate(rate)
                wav.writeframes(values.tobytes())
            cases = [source]
            for extension, codec in [("mp3", "libmp3lame"), ("m4a", "aac"), ("flac", "flac"),
                                     ("aiff", "pcm_s24be")]:
                encoded = root / f"tone.{extension}"
                subprocess.run([str(self.encoder), "-nostdin", "-v", "error", "-i", str(source),
                                "-acodec", codec, str(encoded)], check=True)
                cases.append(encoded)
            for index, encoded in enumerate(cases):
                with self.subTest(format=encoded.suffix):
                    info = runner.probe_audio(encoded, self.ffprobe)
                    output = root / f"decoded-{index}.f32"
                    with patch.object(runner, "PROTOCOL_OUTPUT", io.StringIO()):
                        runner.decode_audio(encoded, output, self.ffmpeg, rate, info.duration, info.channels)
                    samples = np.fromfile(output, dtype="<f4").reshape(-1, 2)
                    self.assertGreater(len(samples), 0)
                    self.assertTrue(np.isfinite(samples).all())
                    self.assertAlmostEqual(len(samples) / rate, 0.2, delta=0.04)
                    if encoded.suffix == ".wav":
                        self.assertTrue(np.array_equal(samples[:, 0], samples[:, 1]))
                        np.testing.assert_allclose(samples[:, 0], values.astype(np.float32) / 32768, atol=1e-7)

    def test_float_and_multichannel_inputs_are_not_clipped_or_truncated(self):
        import numpy as np

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cases = [
                ("float.wav", "sine=frequency=440:sample_rate=96000:duration=0.2", "volume=12", 1),
                ("center.wav", "sine=frequency=440:sample_rate=44100:duration=0.2", "pan=5.1|c2=c0", 6),
            ]
            for name, source, filter_string, channels in cases:
                with self.subTest(format=name):
                    encoded = root / name
                    subprocess.run([str(self.encoder), "-nostdin", "-v", "error", "-f", "lavfi", "-i", source,
                                    "-af", filter_string, "-acodec", "pcm_f32le", str(encoded)], check=True)
                    info = runner.probe_audio(encoded, self.ffprobe)
                    self.assertEqual(info.channels, channels)
                    output = encoded.with_suffix(".f32")
                    with patch.object(runner, "PROTOCOL_OUTPUT", io.StringIO()):
                        runner.decode_audio(encoded, output, self.ffmpeg, 44100, info.duration, channels)
                    samples = np.fromfile(output, dtype="<f4").reshape(-1, 2)
                    self.assertTrue(np.isfinite(samples).all())
                    self.assertAlmostEqual(len(samples) / 44100, 0.2, delta=0.001)
                    self.assertGreater(float(np.max(np.abs(samples))), 1 if channels == 1 else 0.05)


if __name__ == "__main__":
    unittest.main()
