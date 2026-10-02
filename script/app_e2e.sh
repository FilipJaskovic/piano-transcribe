#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-Debug}"
APP_BUNDLE="${APP_BUNDLE:-$ROOT_DIR/build/DerivedData/Build/Products/$CONFIGURATION/Piano transcribe.app}"
PYTHON="${PIANO_TRANSCRIBE_PYTHON:-$ROOT_DIR/.venv/bin/python}"

if [[ ! -x "$PYTHON" ]]; then
  echo "Missing Python backend. Set PIANO_TRANSCRIBE_PYTHON or run Packaging/build_backend_dev.sh." >&2
  exit 1
fi

if [[ "${PIANO_TRANSCRIBE_SKIP_BUILD:-0}" != "1" ]]; then
  CONFIGURATION="$CONFIGURATION" "$ROOT_DIR/script/build_and_run.sh" --build
fi

exec "$PYTHON" "$ROOT_DIR/script/e2e.py" "$APP_BUNDLE" --debug-root "$ROOT_DIR" --python "$PYTHON"
