# Piano transcribe V2 review

Reviewed: 2026-10-02. Source snapshot: `3b5fb2f` on `main`.

This is a whole-app audit, not a review of a particular diff. The repository was clean at the start. Five agents reviewed Swift, Python, release tooling, transcription research, and separation research. No app source, installed app, preferences, credentials, or GitHub release was changed.

Read the [V2 plan](/Users/filip/Developer/piano-transcribe/V2_PLAN.md) for the proposed work and the [model research](/Users/filip/Developer/piano-transcribe/V2_MODEL_RESEARCH.md) for alternatives.

## Findings

P1 means a high-impact correctness or distribution defect. P2 means a significant reliability, quality, or coverage gap. Static risks are not presented as observed production failures.

### 1. P1: A failed export can delete the previous output

[FileAccess.saveOutput](/Users/filip/Developer/piano-transcribe/PianoTranscribe/Services/FileAccess.swift:66) removes an existing destination before copying the replacement. The same helper saves MIDI and both WAV stems. A repeat job can silently overwrite previous work, and a failed copy can leave no output at all.

Verification: an isolated Swift harness compiled the actual repository helper, seeded an existing MIDI file, and supplied a missing working file. The copy failed, and the previous output was gone.

V2 needs an explicit collision policy and same-volume staging followed by atomic replacement of each file. Never delete the existing output before a valid replacement is ready.

### 2. P1: Cancellation does not own the complete job lifetime

[AppModel.cancel](/Users/filip/Developer/piano-transcribe/PianoTranscribe/Services/AppModel.swift:204) immediately marks the job cancelled. [The admission guard](/Users/filip/Developer/piano-transcribe/PianoTranscribe/Services/AppModel.swift:110) then allows another job, although the old task and Python process may still be running.

The service shares one `currentProcess`. Status and log callbacks do not carry a job ID. An old task can therefore update the new job's UI. There are no cancellation checks between preprocessing, transcription, and saving. [runProcess](/Users/filip/Developer/piano-transcribe/PianoTranscribe/Services/TranscriptionService.swift:152) also launches unconditionally after registering its cancellation handler.

Verification: an isolated Swift test confirmed that an already-cancelled task invokes `onCancel` and still executes the operation. A cancellation handler alone does not prevent process launch. The overlapping-job race is established by code inspection, not an app UI reproduction.

V2 needs a `cancelling` state, job-scoped process ownership, cancellation checks at stage boundaries, and exactly one terminal event after teardown.

### 3. P1: The packaged Python environments are not standalone

[Release staging](/Users/filip/Developer/piano-transcribe/Packaging/build_backend_release.sh:110) copies both developer virtual environments. It does not bundle their external Python frameworks and standard libraries.

Read-only `otool -L` inspection found these dependencies in the local interpreters:

```text
Transkun: /opt/homebrew/Cellar/python@3.12/3.12.13/Frameworks/Python.framework/Versions/3.12/Python
Separator: /opt/homebrew/Cellar/python@3.10/3.10.19_1/Frameworks/Python.framework/Versions/3.10/Python
```

The [workflow](/Users/filip/Developer/piano-transcribe/.github/workflows/build-and-release.yml:69) explicitly allows developer venv staging and tests on the same runner with both base Pythons installed. Success on that runner does not establish clean-Mac portability.

V2 needs redistributable runtimes, a recursive Mach-O dependency audit, and consumer testing of the final relocated artifact.

### 4. P1: Supported M4A separation depends on an unbundled tool

[Separator decoding](/Users/filip/Developer/piano-transcribe/Backend/pc_separator_runner.py:125) falls back from SoundFile to Pydub. That path invokes `ffprobe`. [Release staging](/Users/filip/Developer/piano-transcribe/Packaging/build_backend_release.sh:147) includes only `ffmpeg`.

Verification: an in-memory AAC-in-MP4 fixture failed with `FileNotFoundError: ffprobe` under a clean PATH, even when Pydub's converter pointed directly to the working bundled FFmpeg. No model inference was needed. The ordinary Transkun runner has a probing workaround, but the separator does not.

V2 needs one tested decoder and explicit bundled paths for both tools.

### 5. P2: Quitting can leave inference running

[AppDelegate](/Users/filip/Developer/piano-transcribe/PianoTranscribe/App/PianoTranscribeApp.swift:36) implements launch handling but no termination policy. There is no shutdown coordination with the job service.

Verification: an isolated Foundation parent launched a child process and exited. The child continued with parent PID 1. This verifies subprocess behavior; the real app was not quit during transcription.

V2 needs a deliberate quit policy that stops and awaits the job's subprocesses. Closing a window and quitting the application must have distinct behavior.

### 6. P2: Long recordings still require memory proportional to duration

[HDMC input decoding](/Users/filip/Developer/piano-transcribe/Backend/pc_separator_runner.py:125) loads the complete track. [Inference](/Users/filip/Developer/piano-transcribe/Backend/pc_separator_runner.py:205) keeps the full tensor. Upstream [split application](/Users/filip/Developer/piano-transcribe/External/pc-separation/model/demucs/apply.py:202) allocates full-track estimates and overlap weights.

Chunking reduced activation memory, but it did not make the pipeline bounded-memory. One stereo float32 track at 44.1 kHz is about 1.27 GB per hour, before estimates, copies, and model activations. The current HDMC window is 40 seconds. [Transkun input](/Users/filip/Developer/piano-transcribe/Backend/transkun_runner.py:188) is also decoded in full.

The allocation structure is verified. The current out-of-memory threshold is not measured. V2 needs long-recording measurements and streaming or disk-backed buffers, without breaking overlap or note merging.

### 7. P2: Intermediate stems are clipped and reduced to PCM16

[save_audio](/Users/filip/Developer/piano-transcribe/Backend/pc_separator_runner.py:145) clamps predictions to `[-1, 1]` and writes WAV without a subtype. SoundFile defaults WAV to PCM16. This also changes the piano intermediary passed to Transkun.

The conversion is verified. Its audible and transcription impact is not measured. V2 needs float32 intermediates and an explicit user-export policy for gain, clipping, and precision.

### 8. P2: Exporting three files can produce an unexplained partial result

[TranscriptionService](/Users/filip/Developer/piano-transcribe/PianoTranscribe/Services/TranscriptionService.swift:92) saves MIDI first, then each stem. A later failure leaves some outputs saved while the app reports only failure. Working job folders also have no cleanup policy. [Job directory creation](/Users/filip/Developer/piano-transcribe/PianoTranscribe/Services/FileAccess.swift:76) has no matching lifecycle cleanup.

V2 needs per-artifact results, retryable export, and bounded cache retention. Multiple ordinary files cannot be replaced as one filesystem transaction. Stage all outputs first, replace each atomically, and report any partial publication honestly.

### 9. P2: Dependencies and weights are not reproducibly locked

[requirements-transkun.lock](/Users/filip/Developer/piano-transcribe/Backend/requirements-transkun.lock:4) leaves Torch and most dependencies unpinned. [Separator setup](/Users/filip/Developer/piano-transcribe/Packaging/build_pc_separation_release.sh:30) resolves current package versions on every build and installs an editable checkout.

The separator source commit is pinned, but download scripts generate checksums after fetching files. Those checksums inventory a download; they do not compare it with a committed trusted digest. Existing HDMC files are accepted for being present.

[Transkun checkpoint loading](/Users/filip/Developer/piano-transcribe/Backend/transkun_runner.py:179) ignores missing and unexpected keys from `strict=False`. Both backends use pickle-capable checkpoint loading. No evidence shows that the current checkpoints are wrong, but incompatible or changed assets can be accepted without a useful diagnosis.

V2 needs exact dependency locks, approved asset digests, config identity, and an explicit state-dict compatibility policy.

### 10. P2: FFmpeg and release checks do not meet the planned distribution policy

The actual staged imageio FFmpeg reports `--enable-gpl`, `--enable-libx264`, and `--enable-libx265`. This differs from the plan's LGPL-compatible build. [Bundled notices](/Users/filip/Developer/piano-transcribe/Packaging/build_backend_release.sh:155) are preliminary lists rather than complete component notices. This does not establish that subprocess use automatically makes the Swift app GPL.

[Readiness checking](/Users/filip/Developer/piano-transcribe/Packaging/check_release_readiness.sh:27) ignores signature verification failure. The [tag workflow](/Users/filip/Developer/piano-transcribe/.github/workflows/build-and-release.yml:69) always skips notarization and publishes explicitly labelled developer DMGs. Merely adding credentials will not wire signing into that workflow.

V2 needs distinct developer and public-release paths. Developer ID is not a prerequisite for publishing a GitHub download, but signed and notarized delivery is the recommended normal-user channel. Unsigned artifacts require an explicit, separately tested distribution policy.

### 11. P2: Existing tests cannot establish useful transcription quality

`Tests/` is empty, and [the scheme](/Users/filip/Developer/piano-transcribe/PianoTranscribe.xcodeproj/xcshareddata/xcschemes/PianoTranscribe.xcscheme:31) has no test targets. Backend and app fixtures use one second of silence. [Release E2E assertions](/Users/filip/Developer/piano-transcribe/script/release_app_e2e.sh:68) check existence and size, which a valid empty MIDI file can satisfy.

Startup environment hooks exercise integration, not real Finder selection, drag and drop, or cancellation. Tests do not cover real notes, compressed separation, long recordings, failed replacement, or partial exports.

[The default app test](/Users/filip/Developer/piano-transcribe/script/app_e2e.sh:130) also inherits the persisted checkpoint. Benchmark automation [writes the user's real preference](/Users/filip/Developer/piano-transcribe/PianoTranscribe/Services/AppModel.swift:174). Repeated tests can exercise the wrong default and change later user behavior.

V2 needs isolated preferences and a focused suite for lifecycle, export, decoding, real piano quality, and final-artifact portability. Silence remains useful only as a small startup check.

### 12. P3: Several contracts and plan descriptions are stale

- The source-folder default and custom output folder are implemented, but the current job does not retain a complete immutable settings snapshot.
- CPU and separation settings are not persisted like checkpoint and destination settings. All windows share the app-scoped `AppModel`, including importer presentation state. Duplicate-sheet behavior remains untested.
- Logs are unbounded and treat arbitrary pipe chunks as strings rather than framed events. Completion does not explicitly await both output streams draining.
- Version metadata remains `0.1.0` and build `1`; release tags do not establish bundle versions. Backend architecture support is not explicitly validated.
- Supplying only one backend segmentation override can leave the other value `None`. No current UI path supplies these overrides.
- Installed Transkun 2.0.1 already uses `AudioSegment.from_file`; the original plan's MP3-only CLI rationale is stale.
- No Pedal Ext describes training and evaluation note-duration conventions. It does not mean that Transkun cannot predict pedal events.
- Separation is implemented, so the original plan's future-separation text is historical rather than the current design.

## What remains useful

The native SwiftUI frontend, isolated subprocess approach, app icon, audio-only import rules, input working copy, CPU default, checkpoint selection, configurable destination, and separated stem outputs are useful foundations. Named checkpoint resolution selects the intended packaged or benchmark pair. The HDMC split path does not omit normalization: the model normalizes internally.

These strengths justify a targeted core rewrite rather than replacing the entire app with a new framework.

## Verification limits

- An isolated unsigned Debug build succeeded with the installed macOS 27 SDK and deployment target 26. No app was launched.
- Shell syntax checks passed for packaging and app scripts. All five Python backend files parsed successfully.
- Interpreter linkage, FFmpeg build configuration, output-loss behavior, Swift cancellation semantics, orphan-child behavior, and clean-PATH AAC decoding were inspected or reproduced as described above.
- No full real-recording inference, clean-machine DMG test, Gatekeeper test, visual UI test, or new model benchmark ran in this audit.
- Candidate quality and speed claims are research evidence, not local measurements.
