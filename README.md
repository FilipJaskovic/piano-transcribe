# Piano transcribe

A native macOS 26+ app for local piano audio-to-MIDI transcription with Transkun V2.

V2 removes piano/orchestra separation. The packaged Transkun checkpoint and CPU remain the defaults. Benchmark V2 is optional. No newly researched model is included.

Select or drop MP3, WAV, AIFF, M4A, or FLAC audio. MIDI saves beside the source unless a custom output folder is selected in Settings. Existing outputs are preserved with numbered filenames.

## Development

Use Xcode 26+ and Python 3.12. The app is non-sandboxed. Developer environments are never used as release runtimes.

```bash
./Packaging/build_backend_dev.sh
export PIANO_TRANSCRIBE_PYTHON="$PWD/build/Backend/python/bin/python3.12"
export PIANO_TRANSCRIBE_FFMPEG_BIN="$PWD/build/Backend/bin"
./script/test.sh
./script/build_and_run.sh
./script/app_e2e.sh
```

For an existing development environment, Debug builds accept `PIANO_TRANSCRIBE_PYTHON`, `PIANO_TRANSCRIBE_ROOT`, and an optional `PIANO_TRANSCRIBE_FFMPEG_BIN`. Release builds resolve only bundled runtime and decoder paths.

## Release status

V2's unsigned Apple Silicon DMG passes the full build and independent relocated
offline app tests. The [qualified candidate](https://github.com/FilipJaskovic/piano-transcribe/actions/runs/37070971794)
includes both checkpoints, standalone Python, FFmpeg, FFprobe, and license notices.
It is a testing artifact, not a published release or a Gatekeeper-ready build.
Developer ID signing and notarization still require Apple credentials and a
separate successful qualification run.

See `Packaging/README.md` for release commands and `V2_PLAN.md` for current progress. The original V1 source and plan are preserved on GitHub branch `backup/v1-before-v2-2026-10-02`.
