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
CUSTOM_OUTPUT_DIR="$TMP_DIR/custom-output"
CUSTOM_OUTPUT_MID="$CUSTOM_OUTPUT_DIR/silence-transkun.mid"
CUSTOM_RESULT_JSON="$TMP_DIR/result-custom-output.json"
BAD_MIDI="$TMP_DIR/not-audio.mid"
BAD_RESULT_JSON="$TMP_DIR/result-bad-input.json"
SEPARATION_RESULT_JSON="$TMP_DIR/result-separation-missing.json"

mkdir -p "$CUSTOM_OUTPUT_DIR"

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
  local preprocessor="${4:-}"
  local output_folder="${5:-}"
  local output_destination="source-folder"

  if [[ -n "$output" ]]; then
    rm -f "$output"
  fi
  if [[ -n "$output_folder" ]]; then
    output_destination="custom-folder"
  fi
  rm -f "$result"

  local open_args=(
    -n "$APP_BUNDLE"
    --env "PIANO_TRANSCRIBE_ROOT=$ROOT_DIR"
    --env "PIANO_TRANSCRIBE_AUTORUN_INPUT=$input"
    --env "PIANO_TRANSCRIBE_AUTORUN_RESULT_FILE=$result"
    --env "PIANO_TRANSCRIBE_AUTORUN_OUTPUT_DESTINATION=$output_destination"
    --env "PIANO_TRANSCRIBE_AUTORUN_REVEAL=0"
    --env "PIANO_TRANSCRIBE_AUTORUN_QUIT=1"
  )

  if [[ -n "$output" ]]; then
    open_args+=(--env "PIANO_TRANSCRIBE_AUTORUN_OUTPUT=$output")
  fi

  if [[ -n "$preprocessor" ]]; then
    open_args+=(--env "PIANO_TRANSCRIBE_AUTORUN_PREPROCESSOR=$preprocessor")
  fi

  if [[ -n "${PIANO_TRANSCRIBE_PC_SEPARATION_ROOT:-}" ]]; then
    open_args+=(--env "PIANO_TRANSCRIBE_PC_SEPARATION_ROOT=$PIANO_TRANSCRIBE_PC_SEPARATION_ROOT")
  fi

  if [[ -n "${PIANO_TRANSCRIBE_PC_SEPARATION_PYTHON:-}" ]]; then
    open_args+=(--env "PIANO_TRANSCRIBE_PC_SEPARATION_PYTHON=$PIANO_TRANSCRIBE_PC_SEPARATION_PYTHON")
  fi

  if [[ -n "$output_folder" ]]; then
    open_args+=(--env "PIANO_TRANSCRIBE_AUTORUN_OUTPUT_FOLDER=$output_folder")
  fi

  /usr/bin/open "${open_args[@]}"

  for _ in {1..120}; do
    if [[ -f "$result" ]]; then
      return 0
    fi
    sleep 1
  done

  echo "Timed out waiting for app result: $result" >&2
  return 1
}

launch_and_wait "$INPUT_WAV" "" "$RESULT_JSON"
".venv/bin/python" - <<PY
import json
from pathlib import Path

result = json.loads(Path("$RESULT_JSON").read_text())
assert result["status"] == "completed", result
assert result["outputExists"] is True, result
assert result["output"] == "$OUTPUT_MID", result
assert Path("$OUTPUT_MID").stat().st_size > 0, result
print("App E2E audio -> MIDI OK:", "$OUTPUT_MID")
PY

launch_and_wait "$INPUT_WAV" "" "$CUSTOM_RESULT_JSON" "" "$CUSTOM_OUTPUT_DIR"
".venv/bin/python" - <<PY
import json
from pathlib import Path

result = json.loads(Path("$CUSTOM_RESULT_JSON").read_text())
assert result["status"] == "completed", result
assert result["outputExists"] is True, result
assert result["output"] == "$CUSTOM_OUTPUT_MID", result
assert Path("$CUSTOM_OUTPUT_MID").stat().st_size > 0, result
print("App E2E custom output folder OK:", "$CUSTOM_OUTPUT_MID")
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

if [[ "${PIANO_TRANSCRIBE_TEST_SEPARATOR:-0}" == "1" ]]; then
  launch_and_wait "$INPUT_WAV" "$OUTPUT_MID" "$SEPARATION_RESULT_JSON" "pc-separation"
  ".venv/bin/python" - <<PY
import json
from pathlib import Path

result = json.loads(Path("$SEPARATION_RESULT_JSON").read_text())
assert result["status"] == "completed", result
assert result["outputExists"] is True, result
assert result["output"] == "$OUTPUT_MID", result
assert Path("$OUTPUT_MID").stat().st_size > 0, result
print("App E2E bundled separation OK:", "$OUTPUT_MID")
PY
else
  launch_and_wait "$INPUT_WAV" "" "$SEPARATION_RESULT_JSON" "pc-separation"
  ".venv/bin/python" - <<PY
import json
from pathlib import Path

result = json.loads(Path("$SEPARATION_RESULT_JSON").read_text())
assert result["status"] == "failed", result
assert (
    "separation backend is missing" in result["message"]
    or "pc-separation files" in result["message"]
), result
print("App E2E separation setup error OK")
PY
fi
