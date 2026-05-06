#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE=""
ALLOW_DEV_VENV="0"

usage() {
  cat >&2 <<USAGE
usage: $0 --app <Piano transcribe.app> [--dev-venv-ok]

Stages the Python backend into an already-built app bundle.

Current implementation:
  - copies Backend/transkun_runner.py
  - copies the existing .venv into Contents/Resources/Backend/python
  - copies imageio-ffmpeg's ffmpeg binary into Contents/Resources/Backend/bin
  - writes preliminary license notes

For a fully redistributable release, replace the .venv copy with a standalone
Python 3.12 runtime before notarization.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP_BUNDLE="${2:-}"
      shift 2
      ;;
    --dev-venv-ok)
      ALLOW_DEV_VENV="1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$APP_BUNDLE" ]]; then
  usage
  exit 2
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "App bundle not found: $APP_BUNDLE" >&2
  exit 1
fi

if [[ ! -x "$ROOT_DIR/.venv/bin/python" ]]; then
  echo "Missing backend .venv. Run ./Packaging/build_backend_dev.sh first." >&2
  exit 1
fi

available_kb="$(df -Pk "$ROOT_DIR" | awk 'NR==2 {print $4}')"
required_kb="${REQUIRED_BACKEND_FREE_KB:-6291456}"
if [[ "$available_kb" -lt "$required_kb" ]]; then
  cat >&2 <<MESSAGE
Not enough free disk space to stage the backend.

Available: $((available_kb / 1024)) MiB
Required:  $((required_kb / 1024)) MiB

PyTorch-based backend packaging duplicates a large runtime into the app bundle.
Free disk space or build on GitHub Actions/macOS 26 where the release workflow
has more scratch space.
MESSAGE
  exit 1
fi

if [[ "$ALLOW_DEV_VENV" != "1" ]]; then
  cat >&2 <<'MESSAGE'
Refusing to create a release backend from the developer .venv by default.

The current .venv may reference machine-local Python framework paths. For
developer DMG testing, rerun with --dev-venv-ok. For a real public release, use
a standalone Python 3.12 runtime and then re-run signing/notarization.
MESSAGE
  exit 1
fi

BACKEND_DIR="$APP_BUNDLE/Contents/Resources/Backend"
PYTHON_DIR="$BACKEND_DIR/python"
BIN_DIR="$BACKEND_DIR/bin"
LICENSE_DIR="$BACKEND_DIR/licenses"

rm -rf "$BACKEND_DIR"
mkdir -p "$PYTHON_DIR" "$BIN_DIR" "$LICENSE_DIR"

rsync -aL \
  --delete \
  --exclude '__pycache__' \
  --exclude '*.pyc' \
  "$ROOT_DIR/.venv/" "$PYTHON_DIR/"

install -m 755 "$ROOT_DIR/Backend/transkun_runner.py" "$BACKEND_DIR/transkun_runner.py"

FFMPEG_PATH="$("$ROOT_DIR/.venv/bin/python" - <<'PY'
import imageio_ffmpeg
print(imageio_ffmpeg.get_ffmpeg_exe())
PY
)"

install -m 755 "$FFMPEG_PATH" "$BIN_DIR/ffmpeg"

cat >"$LICENSE_DIR/README.md" <<'EOF'
# License Notices

This directory is a placeholder for release license notices.

Required before public distribution:

- Transkun license
- PyTorch license and notices
- Python runtime license
- FFmpeg license/build configuration
- pydub, pretty_midi, moduleconf, soxr, scipy, numpy, and other dependency notices

Use an LGPL-compatible FFmpeg build unless the whole app distribution is intended
to comply with GPL terms.
EOF

cat >"$BACKEND_DIR/BUILD-NOTES.txt" <<EOF
Backend staged on: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Python: $("$PYTHON_DIR/bin/python" --version 2>&1)
Transkun: $("$PYTHON_DIR/bin/python" - <<'PY'
import transkun
print(transkun.__file__)
PY
)

WARNING: This backend was staged from the developer .venv. It is useful for
developer DMG testing, but it is not yet a clean standalone runtime.
EOF

echo "Backend staged in: $BACKEND_DIR"
