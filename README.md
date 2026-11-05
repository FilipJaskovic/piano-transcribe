# Piano transcribe

Piano transcribe is a macOS app that turns a piano recording into a MIDI file. It runs the [Transkun](https://github.com/Yujia-Yan/Transkun) transcription model on your Mac, so no audio leaves the machine.

It needs macOS 26 or later on Apple Silicon.

## Use the app

1. Drop an MP3, WAV, AIFF, M4A, or FLAC file on the window, or click **Choose Audio**.
2. Wait for the four steps to finish: Prepare, Decode, Transcribe, and Save.
3. Click **Show in Finder** to open the MIDI file.

The app saves `<recording>-transkun.mid` next to the recording. If that file already exists, the app keeps it and saves a numbered copy, such as `<recording>-transkun (2).mid`.

To change where MIDI files go, open **Settings** from the header or press Cmd-,. Settings also selects the model checkpoint and the device:

- **Packaged default** is Transkun V2 No Pedal Ext, the checkpoint that ships with the `transkun` package.
- **Benchmark V2** is the checkpoint from the Transkun model card. CI builds include it. A local build includes it only with `DOWNLOAD_BENCHMARK=1`.
- **CPU** is the default device. **MPS / Metal** is experimental.

## Install

There is no published release yet. Developer ID signing and notarization are not set up ([#4](https://github.com/FilipJaskovic/piano-transcribe/issues/4)), so macOS shows a security warning for any build you make.

To build an unsigned DMG, run this on an Apple Silicon Mac with Xcode 26 and at least 8 GiB free:

```bash
./Packaging/package_dmg.sh --allow-unsigned
```

The DMG contains everything the app needs: Python 3.12, Transkun, the packaged checkpoint, and FFmpeg. It does not need Homebrew, a Python install, or a network connection. [Packaging/README.md](Packaging/README.md) covers signed builds and CI.

## Develop

You need Xcode 26 and Python 3.12. Build the development backend once, then point Debug builds at it:

```bash
./Packaging/build_backend_dev.sh
export PIANO_TRANSCRIBE_PYTHON="$PWD/build/Backend/python/bin/python3.12"
export PIANO_TRANSCRIBE_FFMPEG_BIN="$PWD/build/Backend/bin"
```

Then use these scripts:

- `./script/test.sh` runs the Swift core tests against a fake backend.
- `./script/build_and_run.sh` builds and opens the Debug app.
- `./script/app_e2e.sh` runs the app end to end on generated audio. It never changes your saved settings.

Release builds ignore these environment variables and use only the runtime inside the app bundle.

## Repository layout

- `PianoTranscribe/` is the SwiftUI app.
- `Backend/` is the Python runner that the app starts for each job. [Backend/PROTOCOL.md](Backend/PROTOCOL.md) describes its JSON output.
- `Packaging/` builds and checks the release bundle.
- `Tests/` and `script/` hold the tests.

## Limits

The tests check that the app produces valid MIDI. They do not measure transcription accuracy on real recordings, and memory use on recordings longer than a few minutes is unmeasured. Version 0.2.0 removed the optional piano and orchestra separation from 0.1.0.
