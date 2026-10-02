# Piano transcribe V2 implementation plan

Last updated: 2026-10-03. Branch: `v2-production`.

## Locked scope

Filip authorized implementation and a GitHub backup before rewriting. V2 removes piano/orchestra separation completely. No new model candidates are adopted. The existing packaged Transkun V2 No Pedal Ext checkpoint remains the default, with benchmark V2 optional. CPU remains the default.

V1 source and the original review are backed up at GitHub branch `backup/v1-before-v2-2026-10-02`, commit `14215ef`. The original app installation and developer environments remain untouched.

## Progress

| Work | Status | Acceptance |
| --- | --- | --- |
| GitHub V1 backup | Complete | Backup branch pushed and verified. |
| Remove separator | Complete | Removed from app, backend, packaging, project, and CI. Historical V1 notes retained. |
| Job lifecycle | Complete | Focused lifecycle tests pass. Native Cancel/retry works; Quit during transcription removes the preview, worker, and worker process group. |
| File safety | Complete | Keep-both and concurrent publication tests pass; destination preflight runs before inference; successful and failed job caches are cleaned. |
| Audio and inference | Implemented; integration checks pass | Float decoding and upstream window parity verified; both checkpoint smokes produce notes. A three-minute CPU fixture completes with measured memory; real-recording quality and longer-input scaling remain unmeasured. |
| Focused tests | Passing locally | Swift 6 lifecycle/export/streams suite; ten backend tests; native default/benchmark/custom output/collision/MIDI rejection E2E. Isolated preferences. |
| Native UI refinement | Complete | Native build and E2E pass. Astra on low checked the real idle window, toolbar, Settings, output menu and custom-folder row without clipping; preview left open at Ready. |
| Standalone packaging | In progress | Pinned redistributable Python 3.12, exact dependency locks, bundled non-GPL FFmpeg and FFprobe, licenses and linkage audit. |
| Release workflow | In progress | Separate producer and relocated consumer, strict readiness checks, explicit signed or unsigned policy, no automatic developer-DMG publication. |
| Final qualification | Pending | Build and tests pass; packaged offline app runs without developer paths; remaining signing or clean-machine requirements stated explicitly. |

Statuses change only when the relevant verification has run. Source changes alone do not establish production readiness.

## App contract

- Native SwiftUI, macOS 26+, initially qualified for Apple Silicon.
- MP3, WAV, AIFF, M4A, and FLAC in. MIDI out. MIDI input is rejected.
- Source-folder saving by default, with a persistent custom-folder option.
- Existing MIDI files are preserved. A repeated conversion receives a numbered filename.
- No separator or separated WAV outputs. No newly researched models.
- One active conversion. Settings are frozen for that conversion.
- Job-scoped subprocess cancellation and application-quit cleanup.
- Structured stage and processed-audio progress, concise errors, bounded Details logs.
- Packaged releases require no Python, Homebrew, Conda, account, or model downloads on the user's Mac.

## Engineering work

The app model handles presentation and preferences. `TranscriptionJob` captures input, output, checkpoint, and device. `TranscriptionService` owns one complete job. `ProcessRunner` owns its subprocess and drains stdout and stderr to EOF before completion.

Cancellation checks run before process launch and between pipeline stages. The app remains busy while cancelling and admits no new job until teardown finishes. Test automation opts into ephemeral settings rather than modifying the user's defaults.

Input is copied to an app-controlled job directory. Audio decoding uses explicit FFmpeg and FFprobe paths, preserving float working samples. Inference preserves Transkun's upstream note-merging behavior. Chunked device transfer and disk-backed working samples reduce long-track memory growth.

Output saving uses no-clobber publication and returns the actual final path. Working directories are removed when jobs finish, including failures and cancellation. V2 does not delete legacy V1 caches or original source recordings.

## Release requirements

The release runtime must be a pinned standalone Python distribution, not a copied developer venv. Dependencies, model/config digests, decoder source, architecture, and license notices must be recorded and verified.

Audit nested Mach-O binaries for external Homebrew, runner-toolcache, and developer paths. Build and test the final relocated bundle in GitHub CI. A hosted builder's successful run alone does not prove clean-Mac operation.

The recommended public channel is Developer ID signed and notarized. No valid signing identity was found locally during this run. An explicitly unsigned GitHub channel remains possible, with macOS security warnings, but must not be silently substituted for signed distribution.

Local free disk space was about 560 MiB when implementation started. Large runtime and DMG staging therefore runs in GitHub CI. No user files are deleted to create space.

## Verification

Local results on 2026-10-02: the native Debug build passes. The focused Swift 6 suite passes, including output preflight. Ten backend tests pass across WAV, MP3, M4A, FLAC, and 24-bit AIFF, with mono amplitude, float headroom, multichannel downmix, and upstream window/merge equivalence checks. Synthetic phrase smokes produce four valid notes for the packaged default and five for benchmark V2. These are integration checks, not accuracy benchmarks.

Native app E2E passes for the packaged default, benchmark V2, source-folder and custom-folder output, preserving an existing result, and rejecting MIDI input. The initial restricted-shell GUI launch aborted before app code; the exact test passes with GUI registration permitted. The installed V1 app and user preferences were not changed.

After the native UI rewrite, the Debug build and all seven focused Swift test groups pass again. Native E2E passes again for both checkpoints and all output/input scenarios. Astra on low verified the actual idle window, toolbar actions, Settings, native output menu and custom-folder Choose row, then restored Audio folder output and left the isolated preview open at Ready. A previous inspection session hit a ScreenCaptureKit capture error in a folder dialog; the final limited native inspection passed. Visual inspection of every running/error state and real Finder drag/drop remains a test gap, not a claimed result.

Astra subsequently verified the real native audio importer, active conversion layout, Cancel returning to Cancelled with usable controls, successful retry, and Saved/Show in Finder state without clipping. Quit during active transcription removed the app, Python worker, and worker process group; the isolated preview was relaunched at Ready. It initially lacked developer launch variables; relaunching with the explicit development environment fixed that setup issue. Preparing was too brief to capture, and actual Finder drag/drop remains unverified.

A 180-second synthetic repeated phrase completes on CPU in 29.62 seconds, with 2,247,458,816 bytes maximum resident memory (about 2.1 GiB), and produces 192 valid note events. This local development-runtime measurement checks sustained execution, not accuracy on real piano recordings or bounded memory for arbitrarily long inputs.

Packaging scripts pass shell syntax checks, workflow YAML parsing, project lint, and five Mach-O dependency-gate tests. GitHub run `37068300848` passed the Swift/backend contract job and installed the pinned standalone Python runtime, all backend dependencies, and legal notices. It then failed at FFmpeg's host-compiler header check. The failure reproduced locally: the host compiler lacked the SDK flags, unlike the target compiler. The recipe now supplies both, enables the correct `pcm_f32le` muxer, and preserves configure diagnostics. The resulting LGPL FFmpeg/FFprobe build passes locally; a Transkun smoke using these exact binaries produces four valid notes.

The complete standalone DMG, relocated offline consumer, signing, and notarization have not yet been qualified. Do not label this snapshot production-ready.

GitHub run `37069452591` passed the repaired FFmpeg build, standalone backend smoke, and native Debug E2E with both checkpoints. The complete bundle audit then rejected upstream wheel build-machine rpaths and mistook dylib install IDs for load dependencies. The packaging repair distinguishes actual dylib loads, normalizes only verified pinned-wheel paths, and re-signs modified nested binaries before import. External dependency rejection remains strict; the final rerun is still required.

Run focused Swift tests with fake workers for pre-launch cancellation, overlapping admission, restart, pipe tails, split UTF-8, nonzero exit, signal exit, and cache cleanup. Verify that a failed output write preserves an older file and that filename collisions keep both outputs.

Run decoder tests with audible fixtures and differing formats, rates, channel counts, and sample widths. Parse MIDI outputs instead of accepting only nonzero file size. Check both Transkun checkpoints with exact model/config pairing.

Run actual app integration in test mode for packaged-default, source-folder output, custom output, repeated output, and MIDI rejection. Track each test process by PID rather than killing every app with the same name.

Qualify the final bundle offline with a clean environment and a relocated path. Record long-recording peak memory and runtime separately from short integration tests. A synthetic tone or silence is not evidence of real piano transcription quality.

## Deferred

No frontend framework replacement, plugin platform, cloud processing, remote audio upload, model marketplace, MIDI editor, notation engine, or batch-parallel inference is part of this rewrite. Filip explicitly requested direct native UI implementation without more mocks. Computer-use verification is delegated to Astra on low.
