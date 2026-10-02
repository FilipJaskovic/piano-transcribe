#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ALLOW_UNSIGNED=0
if [[ $# == 1 && "$1" == '--allow-unsigned' ]]; then
  ALLOW_UNSIGNED=1
elif [[ $# != 0 ]]; then
  echo "usage: $0 [--allow-unsigned]" >&2
  exit 2
fi
VERSION="${VERSION:-2.0.0}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'VERSION must be x.y.z.' >&2; exit 2; }
if [[ "$ALLOW_UNSIGNED" == 0 ]]; then
  : "${SIGN_IDENTITY:?Developer ID identity required}" "${APPLE_ID:?Apple ID required}" \
    "${APPLE_TEAM_ID:?Apple team required}" "${APPLE_APP_PASSWORD:?App-specific password required}"
  [[ "$SIGN_IDENTITY" == 'Developer ID Application:'* ]] || { echo 'Expected Developer ID Application identity.' >&2; exit 1; }
fi
cd "$ROOT_DIR"
mkdir -p build dist
APP="$ROOT_DIR/build/DerivedData/Build/Products/Release/Piano transcribe.app"
xcodebuild -project PianoTranscribe.xcodeproj -scheme PianoTranscribe -configuration Release \
  -derivedDataPath "$ROOT_DIR/build/DerivedData" ARCHS=arm64 CODE_SIGNING_ALLOWED=NO \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="${BUILD_NUMBER:-2}" build
"$ROOT_DIR/Packaging/build_backend_release.sh" --app "$APP"
SIGN_ARGS=()
SUFFIX=''
if [[ "$ALLOW_UNSIGNED" == 1 ]]; then
  SIGN_ARGS+=(--allow-unsigned)
  SUFFIX='-unsigned'
fi
"$ROOT_DIR/Packaging/sign_app.sh" "$APP" "${SIGN_ARGS[@]}"
if [[ "$ALLOW_UNSIGNED" == 0 ]]; then
  "$ROOT_DIR/Packaging/notarize.sh" "$APP"
fi
"$ROOT_DIR/Packaging/check_release_readiness.sh" "$APP" "${SIGN_ARGS[@]}"
DMG="$ROOT_DIR/dist/piano-transcribe-$VERSION-arm64$SUFFIX.dmg"
STAGING="$(mktemp -d "$ROOT_DIR/build/dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/Piano transcribe.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname 'Piano transcribe' -srcfolder "$STAGING" -ov -format UDZO "$DMG"
if [[ "$ALLOW_UNSIGNED" == 0 ]]; then
  codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"
  "$ROOT_DIR/Packaging/notarize.sh" "$DMG"
fi
(cd "$ROOT_DIR/dist" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "DMG ready: $DMG"
