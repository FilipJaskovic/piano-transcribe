#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_DIR="${PIANO_TRANSCRIBE_PC_SEPARATION_ROOT:-$ROOT_DIR/External/pc-separation}"
ENV_DIR="${PIANO_TRANSCRIBE_PC_SEPARATION_ENV:-$ROOT_DIR/.pc-separation-env}"
DOWNLOAD_WEIGHTS=0

for arg in "$@"; do
  case "$arg" in
    --download-weights)
      DOWNLOAD_WEIGHTS=1
      ;;
    *)
      echo "unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

if [[ ! -d "$REPO_DIR/.git" ]]; then
  mkdir -p "$(dirname "$REPO_DIR")"
  git clone https://github.com/yiitozer/pc-separation.git "$REPO_DIR"
fi

if ! command -v conda >/dev/null 2>&1; then
  cat >&2 <<EOF
Missing conda. pc-separation has a separate older dependency stack, so install
Miniconda/Mambaforge or create your own environment, then set:

export PIANO_TRANSCRIBE_PC_SEPARATION_ROOT="$REPO_DIR"
export PIANO_TRANSCRIBE_PC_SEPARATION_PYTHON="/path/to/env/bin/python"

Then run:
python Backend/pc_separator_runner.py --doctor --repo "$REPO_DIR"
EOF
  exit 1
fi

if [[ ! -x "$ENV_DIR/bin/python" ]]; then
  conda env create -p "$ENV_DIR" -f "$REPO_DIR/environment.yml"
fi

conda run -p "$ENV_DIR" python -m pip install -e "$REPO_DIR"

if [[ "$DOWNLOAD_WEIGHTS" == "1" ]]; then
  conda run -p "$ENV_DIR" gdown --folder \
    "https://drive.google.com/drive/folders/1-zcdkHWUcfehaTjoxp-eCjAjZevDGxSu" \
    -O "$REPO_DIR/checkpoints"
fi

conda run -p "$ENV_DIR" python "$ROOT_DIR/Backend/pc_separator_runner.py" --doctor --repo "$REPO_DIR"

cat <<EOF
pc-separation backend ready.

Use these values when launching the app outside script/build_and_run.sh:
export PIANO_TRANSCRIBE_PC_SEPARATION_ROOT="$REPO_DIR"
export PIANO_TRANSCRIBE_PC_SEPARATION_PYTHON="$ENV_DIR/bin/python"
EOF
