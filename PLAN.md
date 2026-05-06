# Piano transcribe Plan: macOS 26+ Audio-to-MIDI Wrapper

Last updated: 2026-05-06

This file is the persistent build plan for Piano transcribe, a native macOS wrapper around Transkun V2. Update the progress tracker as milestones are completed.

## Progress Tracker

Current status: Developer MVP is implemented and verified. Backend WAV/MP3 smoke tests pass on CPU, the SwiftUI app builds and launches, automated app E2E audio -> MIDI passes, `.mid` input rejection passes, and the private GitHub repository has a macOS 26 workflow for backend smoke testing, app E2E testing, Release building, DMG packaging, and artifact upload.

| Milestone | Status | Notes |
| --- | --- | --- |
| 1. Terminal proof of concept | Complete | Python 3.12 venv created. WAV and MP3 audio -> MIDI smoke tests pass on CPU. |
| 2. SwiftUI shell | Complete | Main window, drop zone, file importer, device picker, status, logs, settings, and cancel command are implemented. |
| 3. Swift-to-Python integration | Complete | `TranscriptionService` invokes Python with `Process`, captures stdout/stderr, copies `output.mid`, and `script/app_e2e.sh` verifies real app audio -> MIDI plus `.mid` rejection. |
| 4. Release backend packaging | Started | Added scripts and GitHub Actions workflow for Release build, backend staging, signing, DMG creation, artifact upload, and tag releases. Full standalone Python/ffmpeg bundling and license collection are still pending. |
| 5. Signing and notarization | Started | Added signing, entitlement, readiness, and notarization scripts. Current Release app has hardened runtime and empty entitlements, but real notarization still needs Developer ID identity and Apple credentials. |
| Future separation pre-step | Placeholder complete | `AudioPreprocessor`, `NoOpPreprocessor`, and `PianoConcertoSeparationPreprocessor` are present; pc-separation is intentionally not bundled into the Transkun environment. |

Current open work:

- Build a true standalone release backend that does not depend on `.venv`, system Python, or Homebrew.
- Bundle vetted LGPL-compatible `ffmpeg`/`ffprobe` and include license notices.
- Configure Developer ID signing identity and Apple notarization credentials in GitHub Actions secrets.
- Create a tag release after the above release prerequisites are satisfied.

GitHub tracking:

- https://github.com/FilipJaskovic/piano-transcribe/issues/1 - Bundle vetted ffmpeg and license notices.
- https://github.com/FilipJaskovic/piano-transcribe/issues/2 - Configure Developer ID signing and notarization.
- https://github.com/FilipJaskovic/piano-transcribe/issues/3 - Bundle standalone Python 3.12 backend.
- https://github.com/FilipJaskovic/piano-transcribe/issues/4 - Keep pc-separation as a future isolated preprocessor.

## Implementation Log

### 2026-05-06

- Initialized git repository in `/Users/filip/Developer/piano-transcribe`.
- Created backend files:
  - `Backend/transkun_runner.py`
  - `Backend/requirements-transkun.lock`
  - `Backend/smoke_test.py`
  - `Packaging/build_backend_dev.sh`
- Created native macOS Xcode project:
  - `PianoTranscribe.xcodeproj`
  - `PianoTranscribe/App/PianoTranscribeApp.swift`
  - `PianoTranscribe/Views/*`
  - `PianoTranscribe/Models/*`
  - `PianoTranscribe/Services/*`
  - `PianoTranscribe/Support/*`
- Added project-local run tooling:
  - `script/build_and_run.sh`
  - `.codex/environments/environment.toml`
- Verified Xcode build and launch with:

```bash
./script/build_and_run.sh --verify
```

- Built the Python backend with:

```bash
./Packaging/build_backend_dev.sh
```

- Verified backend smoke tests:
  - Silent WAV -> non-empty MIDI.
  - Silent MP3 -> non-empty MIDI.
- Local environment note: `/opt/homebrew/bin/ffmpeg` and `/opt/homebrew/bin/ffprobe` are currently broken because they reference a missing `svt-av1` dynamic library. The dev backend now falls back to `imageio-ffmpeg` for decoding and skips pydub probing when `ffprobe` is broken. Release packaging still needs a vetted bundled ffmpeg/ffprobe with license notices.
- Added release/GitHub infrastructure:
  - `.github/workflows/build-and-release.yml`
  - `Packaging/build_backend_release.sh`
  - `Packaging/package_dmg.sh`
  - `Packaging/sign_app.sh`
  - `Packaging/notarize.sh`
  - `Packaging/README.md`
- The GitHub workflow uses the official `macos-26` GitHub-hosted runner label so CI has macOS 26/Xcode 26 tooling.
- Local DMG packaging attempt reached the Release app build, then stopped while staging the backend because this Mac only had about 172 MiB free. The script now preflights free space and recommends building the artifact in GitHub Actions or freeing local disk space.
- Created private GitHub repository: `FilipJaskovic/piano-transcribe`.
- Pushed branch `main` to GitHub.
- First GitHub Actions run passed:
  - Run ID: `25455656801`
  - Backend smoke test: passed.
  - Release app build: passed.
  - Developer DMG package: passed.
  - DMG artifact upload: passed.
- Added backend health diagnostics:
  - `Backend/doctor.py` verifies Python 3.12, Torch, Transkun, MPS availability, and `ffmpeg`/`ffprobe` state.
  - `Packaging/build_backend_dev.sh` now runs the doctor before the smoke test.
- Added automated app E2E verification:
  - `script/app_e2e.sh` builds the app, launches the real `.app`, sends an autorun audio job through environment variables, verifies a non-empty MIDI output, then verifies `.mid` input rejection.
  - `AppModel.runStartupAutomationIfNeeded()` supports this test without changing the normal user-facing UI.
- Hardened UI/end-to-end error handling:
  - Subprocess failures show a concise user-facing status and keep backend details in the collapsible Details log.
  - Cancellation is treated as cancellation instead of a generic subprocess failure.
- Tightened release signing settings:
  - Bundle identifier is now `com.filipjaskovic.PianoTranscribe`.
  - Release builds disable injected base entitlements.
  - `Packaging/entitlements.plist` is an empty entitlement set for the initial non-sandboxed Developer ID build.
  - `Packaging/check_release_readiness.sh` reports bundle ID, minimum macOS, signing state, entitlements, backend staging, and notarization credential readiness.
- Re-verified locally:
  - `.venv/bin/python Backend/doctor.py`: passed.
  - `./script/app_e2e.sh`: passed.
  - Release `xcodebuild`: passed.
  - `./Packaging/check_release_readiness.sh "build/DerivedData/Build/Products/Release/Piano transcribe.app"`: valid ad-hoc signed Release app with hardened runtime and empty entitlements; distribution still blocked by missing Developer ID identity, missing notarization credentials, and no staged standalone backend in the local build.

## 1. MVP Product Definition

App name: `Piano transcribe`

Folder name: `piano-transcribe`

Swift module/internal target name: `PianoTranscribe`

Platform: macOS 26.0+

Core task: user selects or drops an audio file, app runs Transkun V2 locally, app saves a `.mid` file.

Initial target: piano recordings only.

Future target: optional piano/orchestra separation pre-step before transcription.

Transkun is an audio-to-MIDI piano transcription system. Its packaged CLI is documented as:

```bash
transkun input.mp3 output.mid
```

The current Transkun repo describes V2 as using a transformer architecture and includes a pip package/CLI for transcribing piano performance audio into MIDI. Its PyPI package is `transkun==2.0.1`, released 2024-09-28, with a packaged wheel around 50.8 MB.

## 2. Recommended Architecture

Use a native SwiftUI macOS app as the front end, with a Python backend runner invoked as a subprocess.

This is simpler and safer than trying to port Transkun to Swift/Core ML immediately, because Transkun is a PyTorch project with Python dependencies such as `torch`, `torchaudio`, `pydub`, `soxr`, `pretty_midi`, `moduleconf`, and others.

High-level flow:

```text
User drops/selects audio
        ->
SwiftUI validates file type
        ->
Swift copies selected file into app-controlled temp job folder
        ->
Optional audio normalization/conversion step
        ->
Swift runs bundled Python backend using Process
        ->
Python backend loads Transkun V2 weights/config
        ->
Python backend writes output .mid
        ->
Swift copies/saves MIDI to user-selected location
        ->
Swift shows success + Reveal in Finder
```

Why copy the selected file first:

If the app is sandboxed, file URLs selected by the user may need security-scoped access. The safe pattern is to start accessing the security-scoped URL, copy the file into the app's own temporary/cache directory, then stop accessing the original URL.

## 3. Build Environment and Platform Settings

Use Xcode 26+, SwiftUI, Swift 6 language mode, and set the deployment target to macOS 26.0.

Recommended Xcode settings:

```text
Product Name: Piano transcribe
Bundle Identifier: com.filipjaskovic.PianoTranscribe
Deployment Target: macOS 26.0
Swift Language Version: Swift 6
Signing: Developer ID for outside-App-Store distribution initially
Sandbox: Off for first developer MVP, optional On later
Hardened Runtime: On for notarized distribution
```

For distribution outside the Mac App Store, plan to notarize. Hardened Runtime is required for notarization.

## 4. CPU First, MPS Optional

Default to CPU for the MVP.

PyTorch supports Apple's Metal Performance Shaders backend through the `mps` device on Apple silicon. However, Transkun has an open Metal support issue, so `mps` should be treated as experimental until tested.

Recommended device behavior:

```text
MVP:
  - Default: cpu
  - Hidden/advanced setting: mps experimental
  - Never auto-select mps until quality and crash testing pass

Future:
  - Auto device:
      if mps tested and stable: mps
      else: cpu
```

## 5. Python Version Choice

Use Python 3.12 for the backend.

Python 3.13 removed the `audioop` module after deprecation in Python 3.11, and the last Python version that provided `audioop` was Python 3.12. This matters because audio packages such as pydub-related stacks often encounter `audioop` compatibility issues on Python 3.13+.

Backend recommendation:

```text
Python: 3.12.x
transkun: 2.0.1
torch/torchaudio: pin after local smoke test
ffmpeg: bundled app resource, not Homebrew-only
```

## 6. File Format Support

Transkun's README shows `input.mp3`, and the current `transcribe.py` uses `pydub.AudioSegment.from_mp3(path)` internally.

For the app, do not expose this limitation to the user. Support common audio inputs:

```text
Minimum MVP:
  .mp3

Better MVP:
  .mp3, .wav, .aif, .aiff, .m4a, .flac

Not supported as input:
  .mid, .midi
```

To support non-MP3 formats, use a custom Python runner that calls `AudioSegment.from_file(path)` instead of Transkun's `from_mp3(path)`. Pydub can open WAV files with pure Python, but for non-WAV formats such as MP3 it needs ffmpeg or libav, so bundle ffmpeg or require it explicitly.

FFmpeg licensing must be handled carefully: FFmpeg is LGPL by default, but optional GPL components can make the whole FFmpeg build GPL. Use an LGPL-compatible FFmpeg build if the app is closed-source, and include license notices.

## 7. Project Structure

```text
piano-transcribe/
  PLAN.md
  PianoTranscribe.xcodeproj
  PianoTranscribe/
    PianoTranscribeApp.swift
    ContentView.swift
    DropZoneView.swift
    AppModel.swift
    TranscriptionJob.swift
    TranscriptionService.swift
    PythonBackendManager.swift
    FileAccess.swift
    SettingsView.swift
    ErrorPresenter.swift
    AudioPreprocessor.swift
    Resources/
      AppIcon.icns

  Backend/
    transkun_runner.py
    requirements-transkun.lock
    smoke_test.py

  Packaging/
    build_backend_dev.sh
    build_backend_release.sh
    package_dmg.sh
    entitlements.plist
    notarize.sh

  Tests/
    PianoTranscribeTests/
```

## 8. Swift Data Model

```swift
import Foundation

enum TranscriptionStatus: Equatable {
    case idle
    case preparingBackend
    case copyingInput
    case transcribing
    case savingOutput
    case completed(URL)
    case failed(String)
    case cancelled
}

struct TranscriptionJob: Identifiable, Equatable {
    let id: UUID
    let sourceURL: URL
    let workingInputURL: URL
    let workingOutputURL: URL
    let finalOutputURL: URL
    var status: TranscriptionStatus

    init(sourceURL: URL, workingInputURL: URL, workingOutputURL: URL, finalOutputURL: URL) {
        self.id = UUID()
        self.sourceURL = sourceURL
        self.workingInputURL = workingInputURL
        self.workingOutputURL = workingOutputURL
        self.finalOutputURL = finalOutputURL
        self.status = .idle
    }
}

enum TranskunDevice: String, CaseIterable, Identifiable {
    case cpu
    case mpsExperimental = "mps"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cpu: "CPU"
        case .mpsExperimental: "MPS / Metal (Experimental)"
        }
    }
}
```

## 9. SwiftUI Main UI

Use `fileImporter` for Finder selection.

Core UI requirements:

- Main window title/display name should be `Piano transcribe`.
- Drop zone accepts audio files.
- Finder selection supports `.mp3`, `.wav`, `.aif`, `.aiff`, `.m4a`, `.flac`.
- MIDI input is rejected with a clear unsupported input error.
- Device picker defaults to CPU and includes MPS as experimental.
- Status area shows progress states.
- Log area shows backend output and error details.
- UI remains responsive while transcription runs.

Sketch:

```swift
import SwiftUI
import UniformTypeIdentifiers
import AppKit

extension UTType {
    static let mp3Audio = UTType(filenameExtension: "mp3")!
    static let wavAudio = UTType(filenameExtension: "wav")!
    static let aiffAudio = UTType(filenameExtension: "aiff")!
    static let aifAudio = UTType(filenameExtension: "aif")!
    static let m4aAudio = UTType(filenameExtension: "m4a")!
    static let flacAudio = UTType(filenameExtension: "flac")!
}
```

## 10. Swift File Access Helper

Responsibilities:

- Validate supported input extensions.
- Reject `.mid` and `.midi`.
- Use security-scoped access around user-selected files when needed.
- Copy input into an app-controlled job directory.
- Use unique job directories to avoid collisions.

Sketch:

```swift
import Foundation

enum FileAccessError: LocalizedError {
    case unsupportedInputExtension(String)
    case copyFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedInputExtension(let ext):
            return "Unsupported input type: .\(ext). Please choose an audio file."
        case .copyFailed:
            return "Could not copy the selected file into the app workspace."
        }
    }
}

struct FileAccess {
    static let supportedExtensions: Set<String> = [
        "mp3", "wav", "aif", "aiff", "m4a", "flac"
    ]
}
```

## 11. Swift Backend Manager

For the first Codex-built MVP, allow a developer mode backend that uses a local venv. Then add release packaging.

Developer mode:

```text
repo-root/.venv/bin/python
repo-root/Backend/transkun_runner.py
```

Release mode:

```text
Piano transcribe.app/Contents/Resources/Backend/python/bin/python3.12
Piano transcribe.app/Contents/Resources/Backend/transkun_runner.py
Piano transcribe.app/Contents/Resources/Backend/bin/ffmpeg
Piano transcribe.app/Contents/Resources/Backend/bin/ffprobe
```

## 12. Swift Transcription Service

Responsibilities:

- Resolve backend.
- Create unique job ID and working directory.
- Prepare working input copy.
- Run Python backend via `Process`.
- Pass `--input`, `--output`, and `--device`.
- Set `PYTHONUNBUFFERED=1`.
- Add bundled ffmpeg directory to `PATH` in release builds.
- Capture stdout/stderr.
- Surface nonzero exit status as useful user-facing error.
- Copy `output.mid` to `<input-name>-transkun.mid` next to the input file for MVP.
- Reveal output in Finder on success.
- Support cancellation by terminating the current process.

## 13. Python Backend Runner

Create `Backend/transkun_runner.py`.

Key requirements:

- CLI args:
  - `--input`
  - `--output`
  - `--device cpu|mps`
  - `--segment-hop-size`
  - `--segment-size`
- Emit JSON progress lines to stdout.
- Use `AudioSegment.from_file(...)` instead of `from_mp3(...)`.
- Load Transkun package pretrained `2.0.pt` and `2.0.conf`.
- Use `moduleconf.parseFromFile(...)`.
- Use `transkun.Data.writeMidi(...)`.
- Resample with `soxr` when input sample rate differs from model sample rate.
- Treat MPS as requested-only and fall back to CPU with a warning if unavailable.
- Never require Python 3.13+.

Essential structure:

```python
#!/usr/bin/env python3
import argparse
import json
from pathlib import Path

import moduleconf
import numpy as np
import torch
from pydub import AudioSegment

import transkun
from transkun.Data import writeMidi


def emit(event: str, **payload):
    print(json.dumps({"event": event, **payload}), flush=True)
```

## 14. Backend Requirements File

Create `Backend/requirements-transkun.lock`.

Start with this, then pin exact versions after smoke testing on macOS 26:

```text
# Keep Python at 3.12.x for compatibility.
transkun==2.0.1

# PyTorch stack. Pin exact versions after local macOS 26 smoke test.
torch
torchaudio

# Transkun dependencies from repo/setup.py.
ncls
pretty_midi
scipy
mir_eval
pydub
matplotlib
tensorboard
tqdm
torch_optimizer
sox
soxr
moduleconf

# Useful for future compatibility if someone accidentally uses Python 3.13+.
audioop-lts; python_version >= "3.13"
```

## 15. Developer Setup Script

Create `Packaging/build_backend_dev.sh`.

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

PYTHON_BIN="${PYTHON_BIN:-python3.12}"

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  echo "Missing $PYTHON_BIN. Install Python 3.12 first."
  exit 1
fi

"$PYTHON_BIN" -m venv .venv
. .venv/bin/activate

python -m pip install --upgrade pip setuptools wheel
python -m pip install -r Backend/requirements-transkun.lock

python Backend/smoke_test.py
echo "Backend ready."
```

## 16. Smoke Test

Create `Backend/smoke_test.py`.

Requirements:

- Import `torch` and `transkun`.
- Print Python, Torch, and Transkun paths/versions.
- Generate a one-second silent WAV using the standard library.
- Run `Backend/transkun_runner.py`.
- Verify a non-empty MIDI file is produced.

## 17. Release Packaging Options

Fast developer MVP:

- Use local `.venv`.
- Run from Xcode.
- Enough for quick Codex build and test.

Production packaging:

- Bundle Python 3.12 standalone runtime.
- Bundle installed site-packages.
- Bundle Transkun V2 wheel/package and pretrained files.
- Bundle ffmpeg and ffprobe.
- Bundle backend runner script.
- Include license notices.

`python-build-standalone` is a good candidate for bundling Python because it produces standalone, redistributable Python builds.

Alternative: build the backend runner with PyInstaller in `onedir` mode and place the result inside the Swift app bundle. Avoid onefile packaging for signed/notarized sandboxed distribution.

Suggested release layout:

```text
Piano transcribe.app/
  Contents/
    MacOS/
      Piano transcribe
    Resources/
      Backend/
        python/
          bin/python3.12
          lib/python3.12/...
        site-packages/...
        transkun_runner.py
        bin/
          ffmpeg
          ffprobe
        licenses/
          TRANSKUN_LICENSE
          PYTORCH_LICENSE
          FFMPEG_LICENSE
          PYDUB_LICENSE
```

## 18. Codesigning and Notarization Checklist

Every executable and dynamic library inside the app bundle must be signed.

Checklist:

```bash
# 1. Sign nested backend binaries first.
codesign --force --timestamp --options runtime \
  --sign "Developer ID Application: YOUR NAME (TEAMID)" \
  "Piano transcribe.app/Contents/Resources/Backend/bin/ffmpeg"

codesign --force --timestamp --options runtime \
  --sign "Developer ID Application: YOUR NAME (TEAMID)" \
  "Piano transcribe.app/Contents/Resources/Backend/python/bin/python3.12"

# 2. Sign the app bundle.
codesign --force --deep --timestamp --options runtime \
  --entitlements Packaging/entitlements.plist \
  --sign "Developer ID Application: YOUR NAME (TEAMID)" \
  "Piano transcribe.app"

# 3. Verify.
codesign --verify --deep --strict --verbose=2 "Piano transcribe.app"
spctl --assess --type execute --verbose=4 "Piano transcribe.app"
```

Initial `entitlements.plist` for outside-App-Store release can be minimal:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.cs.allow-jit</key>
  <false/>
  <key>com.apple.security.cs.disable-library-validation</key>
  <false/>
</dict>
</plist>
```

For a sandboxed build, add user-selected file read/write entitlement and keep the security-scoped file-copy approach.

## 19. Error Handling Requirements

Implement clear user-facing errors for:

- User drops a MIDI file instead of audio.
- Unsupported audio extension.
- Python backend missing.
- Transkun package missing or broken.
- ffmpeg/ffprobe missing for compressed formats.
- Transcription subprocess exits nonzero.
- Output MIDI cannot be written.
- User cancels or quits during transcription.
- MPS requested but unavailable.

The UI should never show only a raw traceback. Keep a collapsible details log area for advanced errors.

## 20. Future Separation Pre-Step Design

Keep the MVP pipeline extensible now, but do not implement piano/orchestra separation yet.

The future `pc-separation` repo describes a pipeline for decomposing piano concerto recordings into separate piano and orchestral tracks. It has a different and older dependency profile, including pinned PyTorch 1.13-era packages. Treat it as a separate backend environment or plugin, not something to merge into the Transkun environment immediately.

Design the pipeline like this:

```swift
protocol AudioPreprocessor {
    var id: String { get }
    var displayName: String { get }

    func process(inputURL: URL, jobDirectory: URL) async throws -> URL
}

struct NoOpPreprocessor: AudioPreprocessor {
    let id = "none"
    let displayName = "No preprocessing"

    func process(inputURL: URL, jobDirectory: URL) async throws -> URL {
        inputURL
    }
}

struct PianoConcertoSeparationPreprocessor: AudioPreprocessor {
    let id = "pc-separation"
    let displayName = "Separate piano from orchestra"

    func process(inputURL: URL, jobDirectory: URL) async throws -> URL {
        // Future:
        // 1. Run pc-separation backend.
        // 2. Save piano stem to jobDirectory/piano.wav.
        // 3. Return piano stem URL.
        fatalError("Not implemented in MVP")
    }
}
```

Future UX:

```text
[ ] Separate piano from orchestra before transcription
    Disabled label: Coming later / experimental
```

Future flow:

```text
Input concerto audio
        ->
pc-separation extracts piano stem
        ->
Transkun transcribes piano stem
        ->
MIDI output
```

## 21. Implementation Milestones

### Milestone 1: Terminal Proof of Concept

Deliverable:

```bash
./Packaging/build_backend_dev.sh
. .venv/bin/activate
python Backend/transkun_runner.py --input test.mp3 --output test.mid --device cpu
```

Acceptance criteria:

- Creates non-empty `.mid` file.
- Works with `.mp3`.
- Works with `.wav`.
- Produces readable JSON progress lines.

### Milestone 2: SwiftUI Shell

Deliverable:

- Main window.
- Drop zone.
- Finder file selection.
- Device picker.
- Status area.
- Log area.

Acceptance criteria:

- Dropping/selecting audio updates app state.
- Dropping/selecting `.mid` shows unsupported input error.
- UI remains responsive while transcription runs.

### Milestone 3: Swift-to-Python Integration

Deliverable:

- `TranscriptionService` invokes backend with `Process`.
- stdout/stderr captured.
- `output.mid` copied to final location.
- Reveal in Finder on success.

Acceptance criteria:

- End-to-end audio -> MIDI from app UI.
- Nonzero backend exit shows useful error.
- Multiple jobs do not overwrite each other.

### Milestone 4: Release Backend Packaging

Deliverable:

- Bundled Python 3.12 backend or PyInstaller onedir backend.
- Bundled ffmpeg/ffprobe.
- App runs on a clean macOS 26 machine without Homebrew.

Acceptance criteria:

- No dependency on developer machine `.venv`.
- No dependency on system Python.
- No dependency on Homebrew ffmpeg.

### Milestone 5: Signing and Notarization

Deliverable:

- Signed `.app`.
- Notarized `.dmg`.
- License notices included.

Acceptance criteria:

- Gatekeeper accepts the app.
- App launches by double-click.
- Backend subprocess launches from inside the signed app.

## 22. Final Codex Build Instruction

Build a native SwiftUI macOS 26+ app called Piano transcribe.

The app is a simple local wrapper around the Transkun V2 Python model. It must accept audio files, not MIDI files, via drag/drop or Finder selection. It must run a Python backend script that loads Transkun V2 and writes a MIDI file. Default device is CPU. MPS may exist as an experimental setting but must not be default.

Use SwiftUI for the UI. Use `Process` to invoke `Backend/transkun_runner.py`. Capture stdout/stderr. Show status and logs. Copy selected files into an app-controlled job temp folder before passing them to Python. Save output as `<input-name>-transkun.mid` next to the input file for the MVP.

Create:

- SwiftUI app files.
- `TranscriptionService`.
- `PythonBackendManager`.
- `FileAccess` helper.
- `AudioPreprocessor` placeholder types.
- `Backend/transkun_runner.py`.
- `Backend/requirements-transkun.lock`.
- `Backend/smoke_test.py`.
- `Packaging/build_backend_dev.sh`.

Use Python 3.12 for the backend. Do not rely on Python 3.13+. Bundle or plan to bundle ffmpeg for release. The MVP may use a local `.venv` in DEBUG.

Keep the code structured so a future `AudioPreprocessor` step can be inserted before Transkun. Add a placeholder `NoOpPreprocessor` and a not-yet-implemented `PianoConcertoSeparationPreprocessor` for future pc-separation support.

## Source Links From Original Plan

- Transkun GitHub: https://github.com/yujia-yan/transkun
- Transkun requirements: https://github.com/Yujia-Yan/Transkun/blob/main/requirements.txt
- Apple security-scoped resources: https://developer.apple.com/documentation/Foundation/URL/startAccessingSecurityScopedResource%28%29
- Xcode system requirements: https://developer.apple.com/xcode/system-requirements/
- Hardened Runtime: https://developer.apple.com/documentation/security/hardened-runtime
- PyTorch on Metal: https://developer.apple.com/metal/pytorch/
- Transkun issues: https://github.com/Yujia-Yan/Transkun/issues
- Python `audioop`: https://docs.python.org/3/library/audioop.html
- Pydub: https://github.com/jiaaro/pydub
- FFmpeg legal: https://www.ffmpeg.org/legal.html
- SwiftUI `fileImporter`: https://developer.apple.com/documentation/swiftui/view/fileimporter%28ispresented%3Aallowedcontenttypes%3Aallowsmultipleselection%3Aoncompletion%3A%29
- python-build-standalone: https://github.com/astral-sh/python-build-standalone
- PyInstaller usage: https://pyinstaller.org/en/latest/usage.html
- pc-separation: https://github.com/yiitozer/pc-separation
- pc-separation environment: https://github.com/yiitozer/pc-separation/raw/refs/heads/master/environment.yml
