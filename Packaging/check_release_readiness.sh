#!/usr/bin/env bash
set -euo pipefail

APP_BUNDLE="${1:-}"

if [[ -z "$APP_BUNDLE" || ! -d "$APP_BUNDLE" ]]; then
  echo "usage: $0 <Piano transcribe.app>" >&2
  exit 2
fi

INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST")"
EXECUTABLE="$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
BACKEND_DIR="$APP_BUNDLE/Contents/Resources/Backend"

echo "App bundle: $APP_BUNDLE"
echo "Executable: $EXECUTABLE"
echo "Bundle ID: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
echo "Minimum macOS: $(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO_PLIST" 2>/dev/null || echo 'not set')"

echo
echo "Signing details:"
codesign -dvvv --entitlements :- "$APP_BUNDLE" 2>&1 || true

echo
echo "Verification:"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE" || true

if [[ -d "$BACKEND_DIR" ]]; then
  echo
  echo "Backend staged: yes"
  echo "Backend size: $(du -sh "$BACKEND_DIR" | awk '{print $1}')"
  if [[ -x "$BACKEND_DIR/python/bin/python" ]]; then
    echo "Backend Python: $("$BACKEND_DIR/python/bin/python" --version 2>&1)"
  else
    echo "Backend Python: missing"
  fi
else
  echo
  echo "Backend staged: no"
fi

echo
if [[ -z "${SIGN_IDENTITY:-}" || "${SIGN_IDENTITY:-}" == "-" ]]; then
  echo "Distribution status: not ready. SIGN_IDENTITY is not set to a Developer ID Application identity."
else
  echo "Configured signing identity: $SIGN_IDENTITY"
fi

if [[ -z "${APPLE_ID:-}" || -z "${APPLE_TEAM_ID:-}" || -z "${APPLE_APP_PASSWORD:-}" ]]; then
  echo "Notarization status: credentials not configured."
else
  echo "Notarization status: credentials configured."
fi
