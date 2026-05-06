#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Piano transcribe"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA="$ROOT_DIR/build/DerivedData"
APP_BUNDLE="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
APP_PROCESS="$APP_NAME"

cd "$ROOT_DIR"

if [[ ! -x ".venv/bin/python" ]]; then
  echo "Missing backend .venv. Run ./Packaging/build_backend_dev.sh first." >&2
  exit 1
fi

CONFIGURATION="$CONFIGURATION" ./script/build_and_run.sh --verify
pkill -x "$APP_PROCESS" >/dev/null 2>&1 || true

TMP_DIR="$(mktemp -d)"
trap 'pkill -x "$APP_PROCESS" >/dev/null 2>&1 || true; rm -rf "$TMP_DIR"' EXIT

INPUT_WAV="$TMP_DIR/silence.wav"
OUTPUT_MID="$TMP_DIR/silence-transkun.mid"
RESULT_JSON="$TMP_DIR/result-success.json"
BAD_MIDI="$TMP_DIR/not-audio.mid"
BAD_RESULT_JSON="$TMP_DIR/result-bad-input.json"

export INPUT_WAV BAD_MIDI
".venv/bin/python" - <<'PY'
from pathlib import Path
import os
import struct
import wave

path = Path(os.environ["INPUT_WAV"])
with wave.open(str(path), "w") as wav:
    wav.setnchannels(1)
    wav.setsampwidth(2)
    wav.setframerate(44100)
    for _ in range(44100):
        wav.writeframes(struct.pack("<h", 0))

Path(os.environ["BAD_MIDI"]).write_bytes(
    b"MThd\x00\x00\x00\x06\x00\x00\x00\x01\x00`"
    b"MTrk\x00\x00\x00\x04\x00\xff/\x00"
)
PY

launch_and_wait() {
  local input="$1"
  local output="$2"
  local result="$3"

  rm -f "$output" "$result"
  /usr/bin/open -n "$APP_BUNDLE" \
    --env "PIANO_TRANSCRIBE_ROOT=$ROOT_DIR" \
    --env "PIANO_TRANSCRIBE_AUTORUN_INPUT=$input" \
    --env "PIANO_TRANSCRIBE_AUTORUN_OUTPUT=$output" \
    --env "PIANO_TRANSCRIBE_AUTORUN_RESULT_FILE=$result" \
    --env "PIANO_TRANSCRIBE_AUTORUN_REVEAL=0" \
    --env "PIANO_TRANSCRIBE_AUTORUN_QUIT=1"

  for _ in {1..120}; do
    if [[ -f "$result" ]]; then
      return 0
    fi
    sleep 1
  done

  echo "Timed out waiting for app result: $result" >&2
  return 1
}

launch_and_wait "$INPUT_WAV" "$OUTPUT_MID" "$RESULT_JSON"
".venv/bin/python" - <<PY
import json
from pathlib import Path

result = json.loads(Path("$RESULT_JSON").read_text())
assert result["status"] == "completed", result
assert result["outputExists"] is True, result
assert Path("$OUTPUT_MID").stat().st_size > 0, result
print("App E2E audio -> MIDI OK:", "$OUTPUT_MID")
PY

launch_and_wait "$BAD_MIDI" "$TMP_DIR/not-audio-transkun.mid" "$BAD_RESULT_JSON"
".venv/bin/python" - <<PY
import json
from pathlib import Path

result = json.loads(Path("$BAD_RESULT_JSON").read_text())
assert result["status"] == "failed", result
assert "MIDI files are not valid input" in result["message"], result
print("App E2E MIDI rejection OK")
PY
