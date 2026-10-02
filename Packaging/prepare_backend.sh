#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FREE_KB="$(df -Pk "$ROOT_DIR" | awk 'NR==2 {print $4}')"
if [[ "$FREE_KB" -lt 8388608 ]]; then
  echo 'Standalone backend builds require at least 8 GiB free. Build in GitHub Actions or free disk space.' >&2
  exit 1
fi
DEST="$ROOT_DIR/build/Backend"
rm -rf "$DEST"
mkdir -p "$DEST"
"$ROOT_DIR/Packaging/build_python_runtime.sh"
"$ROOT_DIR/Packaging/build_ffmpeg.sh"
install -m 755 "$ROOT_DIR/Backend/transkun_runner.py" "$DEST/transkun_runner.py"
cp "$ROOT_DIR/Backend/checkpoints.json" "$DEST/checkpoints.json"
cp "$ROOT_DIR/Backend/checkpoints.json" "$DEST/licenses/TRANSKUN-CHECKPOINTS.json"
if [[ "${DOWNLOAD_BENCHMARK:-0}" == 1 ]]; then
  TRANSKUN_BENCHMARK_DIR="${TRANSKUN_BENCHMARK_DIR:-$ROOT_DIR/External/transkun-checkpoints/benchmark-v2}"
  PYTHON_BIN="$DEST/python/bin/python3.12" DEST_DIR="$TRANSKUN_BENCHMARK_DIR" \
    "$ROOT_DIR/Packaging/download_transkun_benchmark_checkpoint.sh"
fi
if [[ -n "${TRANSKUN_BENCHMARK_DIR:-}" ]]; then
  mkdir -p "$DEST/transkun-checkpoints/benchmark-v2"
  cp "$TRANSKUN_BENCHMARK_DIR/checkpoint.pt" "$TRANSKUN_BENCHMARK_DIR/model.conf" \
    "$DEST/transkun-checkpoints/benchmark-v2/"
  if [[ -f "$TRANSKUN_BENCHMARK_DIR/SOURCE.json" ]]; then
    cp "$TRANSKUN_BENCHMARK_DIR/SOURCE.json" "$DEST/transkun-checkpoints/benchmark-v2/"
  fi
fi
"$DEST/python/bin/python3.12" -I -B "$ROOT_DIR/Packaging/verify_backend.py" "$DEST"
