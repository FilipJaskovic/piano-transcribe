#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Piano transcribe"
SCHEME="PianoTranscribe"
PROJECT="PianoTranscribe.xcodeproj"
BUNDLE_ID="com.filipjaskovic.PianoTranscribe"
CONFIGURATION="${CONFIGURATION:-Debug}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/build/DerivedData"
APP_BUNDLE="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cd "$ROOT_DIR"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  build

open_app() {
  local open_args=(-n "$APP_BUNDLE" --env "PIANO_TRANSCRIBE_ROOT=$ROOT_DIR")

  if [[ -n "${PIANO_TRANSCRIBE_PC_SEPARATION_ROOT:-}" ]]; then
    open_args+=(--env "PIANO_TRANSCRIBE_PC_SEPARATION_ROOT=$PIANO_TRANSCRIBE_PC_SEPARATION_ROOT")
  fi

  if [[ -n "${PIANO_TRANSCRIBE_PC_SEPARATION_PYTHON:-}" ]]; then
    open_args+=(--env "PIANO_TRANSCRIBE_PC_SEPARATION_PYTHON=$PIANO_TRANSCRIBE_PC_SEPARATION_PYTHON")
  fi

  /usr/bin/open "${open_args[@]}"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    env \
      "PIANO_TRANSCRIBE_ROOT=$ROOT_DIR" \
      "PIANO_TRANSCRIBE_PC_SEPARATION_ROOT=${PIANO_TRANSCRIBE_PC_SEPARATION_ROOT:-}" \
      "PIANO_TRANSCRIBE_PC_SEPARATION_PYTHON=${PIANO_TRANSCRIBE_PC_SEPARATION_PYTHON:-}" \
      lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
