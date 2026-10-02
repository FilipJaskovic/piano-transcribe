# Backend Protocol

Stdout contains one JSON object per line. Every object has `version: 1` and an
`event` discriminator. Dependency messages and tracebacks go to stderr.

| Event | Fields |
| --- | --- |
| `stage` | `stage`, optional `totalSeconds` |
| `progress` | `stage`, `processedSeconds`, `totalSeconds` |
| `warning` | `message` |
| `result` | `output`, `checkpoint`, actual `device`, `noteCount` |
| `error` | stable `code`, concise `message` |

Stages are `validating`, `loading_model`, `decoding`, `transcribing`, and
`writing_midi`. Progress applies to its stage, not to the entire job. A successful
job ends with one `result` and exit status 0; a failure ends with `error` and exit
status 1. Cancellation uses `error` code `cancelled` and status 130. The caller
must also handle forced process termination without a final event.

The runner accepts only known audio extensions and the two hash-pinned Transkun
2.0.1 checkpoints. It never searches PATH for decoders. Pass absolute `--ffmpeg`
and `--ffprobe` paths or stage both binaries in `Backend/bin` next to the runner.

Decoded audio is float32 stereo PCM on disk. Mono is duplicated without gain
change; multichannel material uses FFmpeg's layout-aware stereo downmix. Windows
are read from a memory map; only one window is transferred to the inference
device. The window adapter preserves Transkun 2.0.1's framing, incomplete-note
merging, and upstream overlap resolver. Note storage grows with the MIDI event
count, but the full decoded recording is not allocated as a PyTorch tensor.

`checkpoints.json` pins both weight and executable configuration hashes. Models
use PyTorch's restricted `weights_only=True` loader and exact state-dict matching.
The runner validates the generated MIDI and publishes it without overwriting an
existing destination. Caller-side user-folder publishing is a separate step.

`smoke_test.py` uses an original additive-synthesis phrase or `--input` recording.
It checks protocol and MIDI structure, not transcription accuracy. Backend tests
include a clean-PATH decoder matrix and exact framing/merging equivalence against
upstream Transkun with a lightweight model double. Real piano quality evaluation
requires an owned recording with reference MIDI.
