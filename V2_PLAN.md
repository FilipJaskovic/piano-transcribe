# Piano transcribe V2 plan

Last updated: 2026-10-02. Status: proposed, not implemented.

This plan follows a whole-app audit of commit `3b5fb2f`. Read the [review](/Users/filip/Developer/piano-transcribe/V2_REVIEW.md) for verified defects and the [research](/Users/filip/Developer/piano-transcribe/V2_MODEL_RESEARCH.md) for model evidence. [PLAN.md](/Users/filip/Developer/piano-transcribe/PLAN.md) remains the historical V1 build record.

## Recommendation

Keep the native SwiftUI app and local subprocess architecture. Rewrite job execution, audio handling, export, and release packaging behind small interfaces. Evaluate new models independently. A new frontend framework or an immediate full CoreML port would add risk without addressing the confirmed defects.

Working priority: better piano and concerto transcription, with reliable offline operation. This remains a planning assumption until Filip selects a different priority.

Preserve the app name **Piano transcribe**, folder `piano-transcribe`, macOS 26 minimum, and the existing GitHub repository. Do not change the installed V1 app or publish a release while planning.

## Product contract

- Accept audio, not MIDI. Preserve MP3, WAV, AIFF, M4A, and FLAC support with tested codec coverage.
- Default to packaged Transkun V2 No Pedal Ext and CPU. Keep benchmark V2 optional. Do not auto-promote an untested checkpoint or MPS path.
- Keep optional piano separation and optional saved piano and orchestra WAV outputs.
- Save MIDI beside the source by default. Preserve the custom output-folder setting and established filenames.
- Never silently destroy an existing output. Offer keep-both or confirmed replacement when names collide.
- Run the selected shipped pipeline entirely offline. Require no user-installed Python, Homebrew, Conda, local checkout, login, or first-run model download.
- Show real stage progress, a useful error, and the resulting files. Keep diagnostic output separate from ordinary status.
- Treat unsupported or protected media clearly. DRM bypass and guaranteed support for arbitrary Apple Music `.movpkg` packages are out of scope.

First-release architecture recommendation: qualify Apple Silicon explicitly. Decide whether Intel support is required before promising it. A universal Swift executable does not make the bundled Python and model runtimes universal.

## Core design

### Job ownership

Create an immutable `JobRequest` containing the source, destination policy, checkpoint identity, device, separation selection, and export options. Changes in Settings affect the next job, not an in-flight job.

Give one `JobCoordinator` ownership of the job, its worker, state transitions, and artifacts. Keep one active job for the initial V2. A queue and parallel inference are not needed yet.

Use this state progression:

```text
preparing -> decoding -> separating, if selected -> transcribing -> exporting -> completed
any active stage -> cancelling -> cancelled
any active stage -> failed
```

Every event carries a job ID. Ignore stale events. Publish exactly one terminal result. Reject a new job until the previous worker has exited and both output streams have drained.

Keep process ownership inside the job, not a shared mutable `currentProcess`. Check cancellation before launch and between stages. Terminate the job's subprocesses, await exit, and apply bounded escalation if they ignore termination. Coordinate application quit with the same shutdown path.

### Backend contract

Use a versioned newline-delimited JSON protocol for stage, progress, warning, result, and error events. Keep stdout machine-readable and stderr diagnostic. Buffer partial lines and UTF-8 fragments before decoding events.

Include job ID, stage, processed seconds, total seconds when known, actual device, model identity, and stable error codes. Do not invent progress percentages for operations that cannot report progress. Bound the UI log and retain a job log for diagnostics.

Retain separate Transkun and HDMC runtimes initially. Use a small transcription adapter and separation adapter. Do not build a general plugin marketplace. A future ONNX separator can implement the same contract after parity and quality tests.

Keep each worker job-scoped initially. A persistent model daemon is deferred until measurements show that startup dominates useful processing time.

### Audio and memory

Inspect and decode input through one tested path using absolute bundled `ffmpeg` and `ffprobe` locations. Reject invalid, empty, non-finite, or unsupported inputs before loading a model. Handle channel conversion explicitly rather than taking the first two channels.

Use float32 working audio and preserve source metadata. Avoid a PCM16 encode-decode step between separation and Transkun. Keep user stem precision and clipping policy explicit.

Measure complete-pipeline memory first. Then replace full-track input and overlap-add buffers with streaming or disk-backed storage where needed. Preserve HDMC overlap behavior and Transkun incomplete-note merging at chunk boundaries.

Provisional target: complete a 30-minute supported recording on an 8 GB Apple Silicon Mac without an out-of-memory kill. Record aggregate worker memory, not only one tensor or process. Set a numerical memory budget after baseline measurements, before choosing final chunk sizes.

### Output ownership

Preflight output directory and collisions before expensive inference. Stage all artifacts and validate MIDI parsing, finite WAV data, duration, rate, and channel count before publication.

Stage replacements on the destination volume and atomically replace each file. Multiple separate files are not one atomic transaction. Record which artifacts were published if a later commit fails, preserve previous files until replacement, and provide retryable export without rerunning inference.

Clean successful and cancelled job caches. Retain failed outputs only for bounded recovery. Expire abandoned jobs on launch. Preserve the original source file throughout the job.

The initial app remains non-sandboxed, matching V1. If sandboxing is introduced later, add persistent folder bookmarks and verify sibling-folder write access explicitly.

## Model decisions

The research supports an evaluation sequence, not a replacement announcement:

1. Compare packaged Transkun, benchmark V2, and official V2 Aug under identical note-duration conventions.
2. Evaluate MuScriptor small and medium as a direct full-mix, note-only piano workflow. Its missing velocity and noncommercial weight terms remain visible.
3. Compare HDMC and BS-RoFormer SW with a fixed Transkun checkpoint. Test SW ONNX parity before selecting a native runtime.
4. Attempt Aria-AMT only if a maintained Mac port or a bounded porting experiment is justified. Upstream CUDA inference is not a supported Mac backend.

Do not bundle every candidate. Keep baseline models during evaluation, then ship only selected engines and checkpoints. Record code and weight terms separately. The earlier public-bundling decision for HDMC does not resolve the terms of unrelated new models.

A direct multi-instrument transcription engine does not produce piano and orchestra WAV files. Retain a separator when the user requests stems. For a generic piano-only separator, label mixture-minus-piano as accompaniment or residual rather than claiming an independently estimated orchestra.

## Native interface

Keep the first screen an audio tool, not a landing page. Make the selected source, actual job configuration, destination, stage, and completed artifacts easy to inspect. Put model and device details in Settings unless the selected workflow requires them.

Proposed behaviors include cancel that stays in the cancelling state, export retry, visible collision choices, and Reveal in Finder for each artifact. Retain keyboard and VoiceOver access. Do not promise a full MIDI editor, notation engine, or large batch system in this rewrite.

Before changing real UI components, create several distinct static mocks with the `html-communication` workflow, publish their URLs, and wait for Filip's choice. No UI redesign is approved by this planning document.

## Release design

Build redistributable Python runtimes from pinned standalone distributions or a validated onedir approach. Install inference-only dependencies from exact locks. Remove editable installs, training-only packages where safely possible, and machine-local paths.

Keep an asset manifest with source revision, runtime version, architecture, weight and config digests, model capabilities, license texts, and provenance. Verify approved hashes before deserializing checkpoints. Reject unexpected state-dict incompatibilities unless a documented adapter explicitly permits them.

Bundle a vetted FFmpeg and FFprobe pair with known build options and complete notices. Audit every nested Mach-O dependency. Reject Homebrew, runner-toolcache, and developer paths. Validate that remaining dependencies resolve to macOS system libraries or inside the bundle.

Separate developer artifacts from public-release artifacts. Derive app and DMG versions from the release tag. Sign nested executable code before the app, verify strictly, and fail public-release checks on required missing assets or invalid signatures.

For the recommended signed channel, wire certificate import, signing, notarization, and stapling into tag CI. Do not request or modify credentials during the review. An explicitly unsigned GitHub channel remains a separate product decision, not an accidental fallback.

Test the final DMG in a separate consumer job without source checkout or Python setup. Relocate the app, isolate preferences and environment, and disable runtime network access. Hosted runners can contain base tools, so add dependency auditing and a clean Mac or VM qualification run. Test the final signed artifact, not only an unsigned builder copy.

## Acceptance evidence

Use focused coverage rather than multiplying silence smoke tests:

- Swift lifecycle tests with fake workers: early cancellation, cancellation between stages, stale events, repeated jobs, quit, and exactly one terminal result.
- Export tests: existing output survives failure, keep-both naming, invalid destination, partial artifact results, and retry without inference.
- Decoder tests: WAV, MP3, M4A, AIFF, and FLAC under clean PATH, including mono, stereo, multichannel, 24-bit, float, and differing sample rates.
- Protocol tests: split JSON lines, split UTF-8, malformed output, startup failure, stderr tail, and signal termination.
- Quality corpus: one owned audible piano phrase plus representative solo and concerto excerpts with suitable reference annotations or stems. Parse notes and compare onset, offset, velocity, and pedal separately.
- Long-file qualification: representative 20-40-minute audio, aggregate memory, runtime, cancellation, cleanup, and chunk-boundary checks on 8 GB and 16 GB Macs.
- Final-artifact test: packaged-default audio to MIDI and separated concerto to MIDI plus stems, offline from a relocated bundle with isolated preferences.

Keep fast deterministic tests in PR CI. Run expensive model comparisons and long-recording qualification for model changes and release candidates. Silence can remain one startup check, but cannot be the quality acceptance criterion.

## Milestones and progress

| Milestone | Status | Deliverable and completion condition |
| --- | --- | --- |
| Audit and primary-source research | Complete | Findings, model shortlist, and this proposed plan. No implementation included. |
| 1. Freeze baseline and decisions | Pending | Licensed corpus, reproducible V1 measurements, required architecture support, distribution channel, and evaluation budgets. |
| 2. Rewrite job and export core | Pending | Job-scoped lifecycle, reliable cancellation and quit, safe output replacement, partial results, cache cleanup, and focused tests. |
| 3. Unify audio and backend protocol | Pending | Deterministic decoder, float intermediates, framed events, model manifests, and long-file memory qualification. |
| 4. Evaluate and select models | Pending | Controlled checkpoint comparison, feasible Mac candidates, documented quality and cost, and an explicit shipping decision. |
| 5. Replace release packaging | Pending | Standalone runtimes, vetted decoder binaries, complete notices, dependency audit, and offline relocated-artifact tests. Can proceed alongside milestones 2-4. |
| 6. Approve and implement native UI | Pending | Published static alternatives, Filip's selection, then accessible UI tied to the new job state and artifact results. |
| 7. Qualify GitHub V2 release | Pending | Final versioned artifact passes the selected signing policy, clean-machine tests, and release acceptance before publication. |

Implement this work incrementally on a V2 branch after authorization. Preserve V1 behavior and configuration migration where practical. Do not replace the daily-driver installation until the new pipeline has passed qualification.

## Deferred work

Defer a general plugin platform, remote transcription, cloud uploads, a persistent inference server, automatic selection of untested GPUs, score-conditioned separation, notation engraving, a MIDI editor, and a broad frontend-framework rewrite.

The next concrete step is milestone 1: establish a reproducible quality and Mac-performance baseline. That evidence determines whether V2 needs a different model, a better separator, a more reliable implementation, or all three.
