#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON="${TEST_PYTHON:-$(command -v python3)}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Compile the production core directly: no Torch, Xcode app launch, or user defaults.
/usr/bin/xcrun swiftc -swift-version 6 -D DEBUG -parse-as-library -module-cache-path "$TMP_DIR/module-cache" \
  "$ROOT_DIR/PianoTranscribe/Models/TranscriptionJob.swift" \
  "$ROOT_DIR/PianoTranscribe/Models/TranscriptionStatus.swift" \
  "$ROOT_DIR/PianoTranscribe/Models/TranskunDevice.swift" \
  "$ROOT_DIR/PianoTranscribe/Models/TranskunCheckpoint.swift" \
  "$ROOT_DIR/PianoTranscribe/Support/Locking.swift" \
  "$ROOT_DIR/PianoTranscribe/Support/SupportedAudioTypes.swift" \
  "$ROOT_DIR/PianoTranscribe/Services/PythonBackendManager.swift" \
  "$ROOT_DIR/PianoTranscribe/Services/FileAccess.swift" \
  "$ROOT_DIR/PianoTranscribe/Services/ProcessRunner.swift" \
  "$ROOT_DIR/PianoTranscribe/Services/TranscriptionService.swift" \
  "$ROOT_DIR/Tests/CoreTests.swift" \
  -o "$TMP_DIR/core-tests"

"$TMP_DIR/core-tests" "$PYTHON" "$ROOT_DIR/Tests/Fixtures/fake_backend.py"
