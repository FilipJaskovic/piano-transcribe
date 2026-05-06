#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Piano transcribe"
SCHEME="PianoTranscribe"
PROJECT="PianoTranscribe.xcodeproj"
CONFIGURATION="${CONFIGURATION:-Release}"
VERSION="${VERSION:-0.1.0}"
DERIVED_DATA="$ROOT_DIR/build/DerivedData"
APP_BUNDLE="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
DIST_DIR="$ROOT_DIR/dist"
DMG_PATH="$DIST_DIR/piano-transcribe-$VERSION.dmg"
ALLOW_DEV_VENV="0"
SKIP_NOTARIZE="0"

usage() {
  cat >&2 <<USAGE
usage: $0 [--dev-venv-ok] [--skip-notarize]

Builds the macOS app, stages the backend, signs the bundle, and creates a DMG.

Environment:
  VERSION                 DMG version suffix. Default: 0.1.0
  CONFIGURATION           Xcode configuration. Default: Release
  SIGN_IDENTITY           Developer ID Application identity. Default: ad-hoc
  DEVELOPMENT_TEAM        Optional Xcode development team
  APPLE_ID                Notarization Apple ID
  APPLE_TEAM_ID           Notarization team ID
  APPLE_APP_PASSWORD      App-specific password
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dev-venv-ok)
      ALLOW_DEV_VENV="1"
      shift
      ;;
    --skip-notarize)
      SKIP_NOTARIZE="1"
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

cd "$ROOT_DIR"
mkdir -p "$DIST_DIR"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="${SIGN_IDENTITY:--}" \
  DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}" \
  build

backend_args=(--app "$APP_BUNDLE")
if [[ "$ALLOW_DEV_VENV" == "1" ]]; then
  backend_args+=(--dev-venv-ok)
fi
"$ROOT_DIR/Packaging/build_backend_release.sh" "${backend_args[@]}"

"$ROOT_DIR/Packaging/sign_app.sh" "$APP_BUNDLE"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$APP_BUNDLE" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [[ "$SKIP_NOTARIZE" != "1" && -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
  "$ROOT_DIR/Packaging/notarize.sh" "$DMG_PATH"
else
  echo "Skipping notarization. Provide Apple credentials or pass --skip-notarize explicitly."
fi

echo "DMG ready: $DMG_PATH"
