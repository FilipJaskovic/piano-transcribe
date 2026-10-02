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

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  build

open_app() {
  local open_args=(-n "$APP_BUNDLE" --env "PIANO_TRANSCRIBE_ROOT=$ROOT_DIR")

  if [[ -n "${PIANO_TRANSCRIBE_PYTHON:-}" ]]; then
    open_args+=(--env "PIANO_TRANSCRIBE_PYTHON=$PIANO_TRANSCRIBE_PYTHON")
  fi

  if [[ -n "${PIANO_TRANSCRIBE_FFMPEG_BIN:-}" ]]; then
    open_args+=(--env "PIANO_TRANSCRIBE_FFMPEG_BIN=$PIANO_TRANSCRIBE_FFMPEG_BIN")
  fi

  if [[ -n "${PIANO_TRANSCRIBE_TRANSKUN_BENCHMARK_DIR:-}" ]]; then
    open_args+=(--env "PIANO_TRANSCRIBE_TRANSKUN_BENCHMARK_DIR=$PIANO_TRANSCRIBE_TRANSKUN_BENCHMARK_DIR")
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
      "PIANO_TRANSCRIBE_PYTHON=${PIANO_TRANSCRIBE_PYTHON:-}" \
      "PIANO_TRANSCRIBE_FFMPEG_BIN=${PIANO_TRANSCRIBE_FFMPEG_BIN:-}" \
      "PIANO_TRANSCRIBE_TRANSKUN_BENCHMARK_DIR=${PIANO_TRANSCRIBE_TRANSKUN_BENCHMARK_DIR:-}" \
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
  --build|build|--verify|verify)
    [[ -x "$APP_BINARY" ]]
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--build|--verify]" >&2
    exit 2
    ;;
esac
