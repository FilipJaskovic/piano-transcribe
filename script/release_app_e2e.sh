#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${1:-$ROOT_DIR/build/DerivedData/Build/Products/Release/Piano transcribe.app}"
APP_PROCESS="Piano transcribe"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "App bundle not found: $APP_BUNDLE" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'pkill -x "$APP_PROCESS" >/dev/null 2>&1 || true; rm -rf "$TMP_DIR"' EXIT

INPUT_WAV="$TMP_DIR/silence.wav"
OUTPUT_MID="$TMP_DIR/silence-transkun.mid"
PIANO_STEM="$TMP_DIR/silence-piano-separated.wav"
ORCHESTRA_STEM="$TMP_DIR/silence-orchestra-separated.wav"
RESULT_JSON="$TMP_DIR/result-release.json"

export INPUT_WAV
python3 - <<'PY'
from pathlib import Path
import os
import struct
import wave

path = Path(os.environ["INPUT_WAV"])
with wave.open(str(path), "w") as wav:
    wav.setnchannels(2)
    wav.setsampwidth(2)
    wav.setframerate(44100)
    for _ in range(44100):
        wav.writeframes(struct.pack("<hh", 0, 0))
PY

pkill -x "$APP_PROCESS" >/dev/null 2>&1 || true
rm -f "$OUTPUT_MID" "$PIANO_STEM" "$ORCHESTRA_STEM" "$RESULT_JSON"

/usr/bin/open \
  -n "$APP_BUNDLE" \
  --env "PIANO_TRANSCRIBE_AUTORUN_INPUT=$INPUT_WAV" \
  --env "PIANO_TRANSCRIBE_AUTORUN_RESULT_FILE=$RESULT_JSON" \
  --env "PIANO_TRANSCRIBE_AUTORUN_OUTPUT_DESTINATION=source-folder" \
  --env "PIANO_TRANSCRIBE_AUTORUN_PREPROCESSOR=pc-separation" \
  --env "PIANO_TRANSCRIBE_AUTORUN_SAVE_STEMS=1" \
  --env "PIANO_TRANSCRIBE_AUTORUN_REVEAL=0" \
  --env "PIANO_TRANSCRIBE_AUTORUN_QUIT=1"

for _ in {1..240}; do
  if [[ -f "$RESULT_JSON" ]]; then
    break
  fi
  sleep 1
done

if [[ ! -f "$RESULT_JSON" ]]; then
  echo "Timed out waiting for release app result: $RESULT_JSON" >&2
  exit 1
fi

python3 - <<PY
import json
from pathlib import Path

result = json.loads(Path("$RESULT_JSON").read_text())
assert result["status"] == "completed", result
assert result["outputExists"] is True, result
assert result["output"] == "$OUTPUT_MID", result
assert Path("$OUTPUT_MID").stat().st_size > 0, result
assert result["stemOutputExists"] is True, result
assert result["stemOutputs"] == ["$PIANO_STEM", "$ORCHESTRA_STEM"], result
assert Path("$PIANO_STEM").stat().st_size > 0, result
assert Path("$ORCHESTRA_STEM").stat().st_size > 0, result
print("Release app E2E bundled separation OK:", "$OUTPUT_MID")
PY
