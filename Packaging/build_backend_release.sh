#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
[[ "${1:-}" == '--app' && -d "${2:-}/Contents" && $# == 2 ]] || {
  echo "usage: $0 --app <Piano transcribe.app>" >&2; exit 2;
}
APP_BUNDLE="$(cd "$2" && pwd)"
"$ROOT_DIR/Packaging/prepare_backend.sh"
BACKEND="$APP_BUNDLE/Contents/Resources/Backend"
mkdir -p "$BACKEND"
rsync -a --delete --exclude '__pycache__' --exclude '*.pyc' "$ROOT_DIR/build/Backend/" "$BACKEND/"
"$BACKEND/python/bin/python3.12" -I -B "$ROOT_DIR/Packaging/verify_backend.py" "$BACKEND"
"$BACKEND/python/bin/python3.12" -I -B "$ROOT_DIR/Packaging/macho_audit.py" "$APP_BUNDLE"
