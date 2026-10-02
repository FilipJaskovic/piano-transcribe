#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:?App bundle required}"
ALLOW_UNSIGNED="${2:-}"
[[ -d "$APP/Contents" && ( -z "$ALLOW_UNSIGNED" || "$ALLOW_UNSIGNED" == '--allow-unsigned' ) ]] || exit 2
INFO="$APP/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO")" == 'com.filipjaskovic.PianoTranscribe' ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO")" == '26.0' ]]
BACKEND="$APP/Contents/Resources/Backend"
PYTHON="$BACKEND/python/bin/python3.12"
"$PYTHON" -I -B "$ROOT_DIR/Packaging/verify_backend.py" "$BACKEND"
"$PYTHON" -I -B "$ROOT_DIR/Packaging/macho_audit.py" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
DETAILS="$(codesign -dvvv "$APP" 2>&1)"
if [[ "$ALLOW_UNSIGNED" != '--allow-unsigned' ]]; then
  grep -q '^Authority=Developer ID Application:' <<< "$DETAILS" || { echo 'Developer ID signature missing.' >&2; exit 1; }
  grep -q 'runtime' <<< "$DETAILS" || { echo 'Hardened runtime missing.' >&2; exit 1; }
  xcrun stapler validate "$APP"
  spctl --assess --type execute --verbose=4 "$APP"
fi
echo 'Release bundle validation passed.'
