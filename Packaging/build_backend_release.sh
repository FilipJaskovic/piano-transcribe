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
  - copies Backend/pc_separator_runner.py
  - copies the existing .venv into Contents/Resources/Backend/python
  - builds and copies pc-separation into Contents/Resources/Backend/pc-separation
  - copies .pc-separation-env into Contents/Resources/Backend/pc-separation-python
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
required_kb="${REQUIRED_BACKEND_FREE_KB:-12582912}"
if [[ "$available_kb" -lt "$required_kb" ]]; then
  cat >&2 <<MESSAGE
Not enough free disk space to stage the backend.

Available: $((available_kb / 1024)) MiB
Required:  $((required_kb / 1024)) MiB

PyTorch-based backend packaging duplicates large Transkun and pc-separation
runtimes into the app bundle. Free disk space or build on GitHub Actions/macOS
26 where the release workflow has more scratch space.
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

PC_REPO_DIR="${PIANO_TRANSCRIBE_PC_SEPARATION_ROOT:-$ROOT_DIR/External/pc-separation}"
PC_ENV_DIR="${PIANO_TRANSCRIBE_PC_SEPARATION_ENV:-$ROOT_DIR/.pc-separation-env}"

BACKEND_DIR="$APP_BUNDLE/Contents/Resources/Backend"
PYTHON_DIR="$BACKEND_DIR/python"
PC_PYTHON_DIR="$BACKEND_DIR/pc-separation-python"
PC_STAGED_REPO="$BACKEND_DIR/pc-separation"
BIN_DIR="$BACKEND_DIR/bin"
LICENSE_DIR="$BACKEND_DIR/licenses"

rm -rf "$BACKEND_DIR"
mkdir -p "$PYTHON_DIR" "$PC_PYTHON_DIR" "$PC_STAGED_REPO" "$BIN_DIR" "$LICENSE_DIR"

"$ROOT_DIR/Packaging/build_pc_separation_release.sh"

rsync -aL \
  --delete \
  --exclude '__pycache__' \
  --exclude '*.pyc' \
  "$ROOT_DIR/.venv/" "$PYTHON_DIR/"

rsync -aL \
  --delete \
  --exclude '__pycache__' \
  --exclude '*.pyc' \
  "$PC_ENV_DIR/" "$PC_PYTHON_DIR/"

rsync -aL \
  --delete \
  --exclude '.git' \
  --exclude '__pycache__' \
  --exclude '*.pyc' \
  --exclude 'PCD' \
  --exclude 'web_content' \
  --exclude 'Separator.ipynb' \
  --exclude 'train.py' \
  "$PC_REPO_DIR/" "$PC_STAGED_REPO/"

if [[ -d "$PC_STAGED_REPO/checkpoints" ]]; then
  find "$PC_STAGED_REPO/checkpoints" -mindepth 1 -maxdepth 1 \
    ! -name 'HDMC20_R_H_HU_HUS' \
    -exec rm -rf {} +
fi

install -m 755 "$ROOT_DIR/Backend/transkun_runner.py" "$BACKEND_DIR/transkun_runner.py"
install -m 755 "$ROOT_DIR/Backend/pc_separator_runner.py" "$BACKEND_DIR/pc_separator_runner.py"
install -m 755 "$ROOT_DIR/Backend/pc_separator_smoke_test.py" "$BACKEND_DIR/pc_separator_smoke_test.py"

FFMPEG_PATH="$("$ROOT_DIR/.venv/bin/python" - <<'PY'
import imageio_ffmpeg
print(imageio_ffmpeg.get_ffmpeg_exe())
PY
)"

install -m 755 "$FFMPEG_PATH" "$BIN_DIR/ffmpeg"

cat >"$LICENSE_DIR/README.md" <<'EOF'
# License Notices

This directory contains preliminary release license and provenance notes.

Included components require notices, including:

- Transkun license
- PyTorch license and notices
- Python runtime license
- FFmpeg license/build configuration
- pydub, pretty_midi, moduleconf, soxr, scipy, numpy, and other dependency notices
- pc-separation source and pretrained weight provenance

Use an LGPL-compatible FFmpeg build unless the whole app distribution is intended
to comply with GPL terms.
EOF

cat >"$LICENSE_DIR/PC-SEPARATION-NOTICE.md" <<EOF
# pc-separation Notice

Source: https://github.com/yiitozer/pc-separation
Pinned commit: ${PC_SEPARATION_COMMIT:-9edb8126a2ebb93852917da06d2ce3619ea15c4d}
Bundled model: HDMC
Weights source: https://drive.google.com/drive/folders/1-zcdkHWUcfehaTjoxp-eCjAjZevDGxSu

The upstream setup.py declares license='MIT', but the repository did not include
a root LICENSE file when this bundle support was added. The pretrained weights
are published separately by the upstream project through Google Drive.
EOF

"$PC_PYTHON_DIR/bin/python" "$BACKEND_DIR/pc_separator_runner.py" \
  --doctor \
  --repo "$PC_STAGED_REPO"

cat >"$BACKEND_DIR/BUILD-NOTES.txt" <<EOF
Backend staged on: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Python: $("$PYTHON_DIR/bin/python" --version 2>&1)
Transkun: $("$PYTHON_DIR/bin/python" - <<'PY'
import transkun
print(transkun.__file__)
PY
)
pc-separation Python: $("$PC_PYTHON_DIR/bin/python" --version 2>&1)
pc-separation repo: $PC_STAGED_REPO
pc-separation checkpoint: $PC_STAGED_REPO/checkpoints/HDMC20_R_H_HU_HUS/hdemucs_best.pth

WARNING: This backend was staged from the developer .venv. It is useful for
developer DMG testing, but it is not yet a clean standalone runtime.
EOF

echo "Backend staged in: $BACKEND_DIR"
