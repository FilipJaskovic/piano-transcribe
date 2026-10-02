#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:?App bundle required}"
ALLOW_UNSIGNED="${2:-}"
[[ -d "$APP/Contents" && ( -z "$ALLOW_UNSIGNED" || "$ALLOW_UNSIGNED" == '--allow-unsigned' ) ]] || exit 2
IDENTITY="${SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" || "$IDENTITY" == '-' ]]; then
  [[ "$ALLOW_UNSIGNED" == '--allow-unsigned' ]] || { echo 'Developer ID identity required; unsigned builds need --allow-unsigned.' >&2; exit 1; }
  IDENTITY='-'
elif [[ "$IDENTITY" != 'Developer ID Application:'* ]]; then
  echo 'Expected a Developer ID Application signing identity.' >&2
  exit 1
fi
PYTHON="$APP/Contents/Resources/Backend/python/bin/python3.12"
"$PYTHON" -I -B "$ROOT_DIR/Packaging/macho_audit.py" "$APP"
LIST="$(mktemp)"
trap 'rm -f "$LIST"' EXIT
"$PYTHON" -I -B "$ROOT_DIR/Packaging/macho_audit.py" --list "$APP" > "$LIST"
ARGS=(--force --sign "$IDENTITY")
if [[ "$IDENTITY" != '-' ]]; then
  ARGS+=(--timestamp --options runtime)
fi
while IFS= read -r -d '' BINARY; do
  codesign "${ARGS[@]}" "$BINARY"
done < "$LIST"
# Nested Mach-O code is signed explicitly; --deep is verification only.
codesign "${ARGS[@]}" --entitlements "$ROOT_DIR/Packaging/entitlements.plist" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
