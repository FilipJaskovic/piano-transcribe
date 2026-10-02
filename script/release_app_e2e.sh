#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${1:-$ROOT_DIR/build/DerivedData/Build/Products/Release/Piano transcribe.app}"
PYTHON="$APP_BUNDLE/Contents/Resources/Backend/python/bin/python3.12"

if [[ ! -x "$PYTHON" ]]; then
  echo "Packaged Python runtime not found: $PYTHON" >&2
  exit 1
fi

OPTIONS=()
if [[ "${PIANO_TRANSCRIBE_TEST_BENCHMARK_CHECKPOINT:-0}" == "1" ]]; then
  OPTIONS+=(--benchmark)
fi
if [[ -n "${PIANO_TRANSCRIBE_PIANO_FIXTURE:-}" ]]; then
  OPTIONS+=(--piano-fixture "$PIANO_TRANSCRIBE_PIANO_FIXTURE")
fi

# A release test uses only the packaged runtime, never the source checkout's venv.
exec /usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" \
  "$PYTHON" -I -B "$ROOT_DIR/script/e2e.py" "$APP_BUNDLE" "${OPTIONS[@]}"
