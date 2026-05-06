#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PC_SEPARATION_COMMIT="${PC_SEPARATION_COMMIT:-9edb8126a2ebb93852917da06d2ce3619ea15c4d}"
REPO_DIR="${PIANO_TRANSCRIBE_PC_SEPARATION_ROOT:-$ROOT_DIR/External/pc-separation}"
ENV_DIR="${PIANO_TRANSCRIBE_PC_SEPARATION_ENV:-$ROOT_DIR/.pc-separation-env}"
PYTHON_BIN="${PYTHON_BIN:-python3.10}"
WEIGHTS_URL="${PIANO_TRANSCRIBE_PC_SEPARATION_WEIGHTS_URL:-https://drive.google.com/uc?id=19iUeyb2RRBsbKeGfayadR7x2wzfmp0e5}"
CHECKPOINT_DIR="$REPO_DIR/checkpoints/HDMC20_R_H_HU_HUS"
CHECKPOINT_FILE="$CHECKPOINT_DIR/hdemucs_best.pth"

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  echo "Missing $PYTHON_BIN. Install Python 3.10 or set PYTHON_BIN=/path/to/python3.10." >&2
  exit 1
fi

mkdir -p "$(dirname "$REPO_DIR")"
if [[ ! -d "$REPO_DIR/.git" ]]; then
  git clone https://github.com/yiitozer/pc-separation.git "$REPO_DIR"
fi

git -C "$REPO_DIR" fetch --tags origin
git -C "$REPO_DIR" checkout --quiet "$PC_SEPARATION_COMMIT"

if [[ ! -x "$ENV_DIR/bin/python" ]]; then
  "$PYTHON_BIN" -m venv "$ENV_DIR"
fi

"$ENV_DIR/bin/python" -m pip install --upgrade pip wheel "setuptools<82"
"$ENV_DIR/bin/python" -m pip install \
  "numpy<2" \
  scipy \
  pandas \
  matplotlib \
  ipython \
  pyyaml \
  tqdm \
  soundfile \
  pydub \
  librosa \
  torch \
  torchaudio \
  asteroid \
  omegaconf \
  diffq \
  mmap_ninja \
  gdown
"$ENV_DIR/bin/python" -m pip install --no-deps -e "$REPO_DIR"

if [[ ! -f "$CHECKPOINT_FILE" ]]; then
  mkdir -p "$CHECKPOINT_DIR"
  "$ENV_DIR/bin/python" -m gdown "$WEIGHTS_URL" -O "$CHECKPOINT_FILE"
fi

if [[ ! -f "$CHECKPOINT_FILE" ]]; then
  cat >&2 <<MESSAGE
Missing HDMC checkpoint after download:
  $CHECKPOINT_FILE

The Google Drive folder layout may have changed. The app bundles only HDMC, so
the release build requires checkpoints/HDMC20_R_H_HU_HUS/hdemucs_best.pth.
MESSAGE
  exit 1
fi

"$ENV_DIR/bin/python" "$ROOT_DIR/Backend/pc_separator_runner.py" --doctor --repo "$REPO_DIR"

(
  cd "$REPO_DIR"
  {
    find config data dsp model solver checkpoints/HDMC20_R_H_HU_HUS -type f \
      ! -name '*.pyc' \
      ! -path '*/__pycache__/*' \
      -print0
    printf '%s\0' README.md setup.py utils.py
  } | xargs -0 shasum -a 256
) >"$REPO_DIR/PIANO_TRANSCRIBE_SHA256SUMS.txt"

cat >"$REPO_DIR/PIANO_TRANSCRIBE_BUNDLE_NOTES.txt" <<EOF
pc-separation source: https://github.com/yiitozer/pc-separation
Pinned commit: $PC_SEPARATION_COMMIT
Weights source: $WEIGHTS_URL
Bundled model: HDMC
Checkpoint: checkpoints/HDMC20_R_H_HU_HUS/hdemucs_best.pth
Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

The upstream setup.py declares license='MIT', but the repository does not
include a root LICENSE file at the pinned commit. The pretrained weights are
distributed by the upstream project through Google Drive.
EOF

cat <<EOF
pc-separation release assets ready.

Repository: $REPO_DIR
Python env: $ENV_DIR
Checkpoint: $CHECKPOINT_FILE
EOF
