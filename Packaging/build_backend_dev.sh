#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT_DIR/Packaging/prepare_backend.sh"
export PATH="$ROOT_DIR/build/Backend/bin:/usr/bin:/bin:/usr/sbin:/sbin"
"$ROOT_DIR/build/Backend/python/bin/python3.12" -I -B "$ROOT_DIR/Backend/smoke_test.py" \
  --ffmpeg "$ROOT_DIR/build/Backend/bin/ffmpeg" --ffprobe "$ROOT_DIR/build/Backend/bin/ffprobe"
echo "Backend ready. For Debug, set PIANO_TRANSCRIBE_PYTHON=$ROOT_DIR/build/Backend/python/bin/python3.12 and PIANO_TRANSCRIBE_FFMPEG_BIN=$ROOT_DIR/build/Backend/bin."
