#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT_DIR/Packaging/sources.env"
[[ "$(uname -sm)" == 'Darwin arm64' ]] || { echo 'Release backend supports Apple Silicon macOS only.' >&2; exit 1; }
CACHE="$ROOT_DIR/build/downloads"
DEST="$ROOT_DIR/build/Backend/python"
LICENSES="$ROOT_DIR/build/Backend/licenses/python"
mkdir -p "$CACHE" "$LICENSES" "$(dirname "$DEST")"
"$ROOT_DIR/Packaging/fetch_verified.sh" "$PYTHON_URL" "$PYTHON_SHA256" "$CACHE/python.tar.gz"
"$ROOT_DIR/Packaging/fetch_verified.sh" "$PYTHON_FULL_URL" "$PYTHON_FULL_SHA256" "$CACHE/python-full.tar.zst"

# The install-only archive omits the license metadata and dependency notices.
LICENSE_TMP="$(mktemp -d "$ROOT_DIR/build/python-licenses.XXXXXX")"
trap 'rm -rf "$LICENSE_TMP"' EXIT
tar -xf "$CACHE/python-full.tar.zst" -C "$LICENSE_TMP" python/PYTHON.json python/licenses
cp "$LICENSE_TMP/python/PYTHON.json" "$LICENSES/PYTHON.json"
cp "$LICENSE_TMP/python/licenses/"* "$LICENSES/"

rm -rf "$DEST"
tar -xzf "$CACHE/python.tar.gz" -C "$(dirname "$DEST")"
PYTHON="$DEST/bin/python3.12"
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1
unset PYTHONHOME PYTHONPATH
"$PYTHON" -I -m pip install --require-hashes --only-binary=:all: --no-deps \
  -r "$ROOT_DIR/Packaging/requirements-build.lock"
"$PYTHON" -I -m pip install --require-hashes --no-build-isolation \
  -r "$ROOT_DIR/Backend/requirements-transkun.lock"
"$PYTHON" -I -m pip check
"$PYTHON" -I -B "$ROOT_DIR/Packaging/relocate_wheel_libraries.py" "$DEST"
cp "$ROOT_DIR/Packaging/relocate_wheel_libraries.py" "$ROOT_DIR/build/Backend/licenses/relocate_wheel_libraries.py"
"$ROOT_DIR/Packaging/fetch_verified.sh" "$TENSORBOARD_LICENSE_URL" "$TENSORBOARD_LICENSE_SHA256" \
  "$ROOT_DIR/build/Backend/licenses/tensorboard-data-server-LICENSE"
"$PYTHON" -I "$ROOT_DIR/Packaging/collect_licenses.py" "$ROOT_DIR/build/Backend/licenses"
cp "$ROOT_DIR/Packaging/sources.env" "$ROOT_DIR/build/Backend/licenses/SOURCES.env"
cp "$ROOT_DIR/Backend/requirements-transkun.lock" "$ROOT_DIR/build/Backend/licenses/requirements-transkun.lock"
echo "Standalone Python backend ready: $PYTHON"
