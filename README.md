# Piano transcribe

A macOS app that turns piano recordings into MIDI files. Transcription runs locally with [Transkun](https://github.com/Yujia-Yan/Transkun).

Requires macOS 26 or later on Apple Silicon. There is no signed release yet.

## Build and run

```bash
./Packaging/build_backend_dev.sh
export PIANO_TRANSCRIBE_PYTHON="$PWD/build/Backend/python/bin/python3.12"
export PIANO_TRANSCRIBE_FFMPEG_BIN="$PWD/build/Backend/bin"
./script/build_and_run.sh
```

To build a DMG, see [Packaging/README.md](Packaging/README.md).
