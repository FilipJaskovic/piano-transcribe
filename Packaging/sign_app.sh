#!/usr/bin/env bash
set -euo pipefail

APP_BUNDLE="${1:-}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENTITLEMENTS="$ROOT_DIR/Packaging/entitlements.plist"

if [[ -z "$APP_BUNDLE" || ! -d "$APP_BUNDLE" ]]; then
  echo "usage: $0 <Piano transcribe.app>" >&2
  exit 2
fi

sign_args=(--force --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  sign_args+=(--timestamp --options runtime)
fi

BACKEND_DIR="$APP_BUNDLE/Contents/Resources/Backend"
if [[ -d "$BACKEND_DIR" ]]; then
  while IFS= read -r -d '' file; do
    if [[ -x "$file" ]] || file "$file" | grep -Eq 'Mach-O|dynamically linked'; then
      codesign "${sign_args[@]}" "$file"
    fi
  done < <(find "$BACKEND_DIR" -type f -print0)
fi

codesign "${sign_args[@]}" --entitlements "$ENTITLEMENTS" --deep "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
