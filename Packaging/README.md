# Package Piano transcribe for release

Release artifacts target Apple Silicon and macOS 26 or later. The app bundles
Transkun, the packaged-default checkpoint, CPython 3.12, FFmpeg, and ffprobe.
The benchmark V2 checkpoint is optional. Users need no Python install, no Homebrew,
and no first-run model download.

## Build an unsigned testing artifact

Run this on an Apple Silicon Mac with Xcode 26 and at least 8 GiB free:

```bash
./Packaging/package_dmg.sh --allow-unsigned
```

The DMG filename ends in `-unsigned`. The app is ad-hoc signed, which keeps its
executables intact on the build Mac. It is not Developer ID signed or notarized,
so Gatekeeper blocks it on other Macs until the user allows it.

## Build a notarized artifact

Install a Developer ID Application certificate. Set `SIGN_IDENTITY` to its
identity and set `APPLE_ID`, `APPLE_TEAM_ID`, and `APPLE_APP_PASSWORD`. Then run:

```bash
./Packaging/package_dmg.sh
```

The script fails before any download if the identity or a credential is missing.
It signs each nested Mach-O file, then the app. It requires an `Accepted`
notarization result, staples and validates the app and the DMG, and runs a
Gatekeeper check.

`VERSION` defaults to `0.2.0`. `BUILD_NUMBER` defaults to `2`.

## GitHub Actions

Pull requests and pushes to `main` run the Swift and backend contract tests and
build the Swift app. They do not build the bundle.

Manual runs and `v*` tags also build the standalone backend and the DMG. A second
job downloads that DMG with no source checkout and no Python setup. It moves the
app, blocks network access, and runs bundle validation and the app E2E test.

A manual run can set `allow_unsigned`. A tag build never falls back to unsigned
packaging. Signed builds need these repository secrets:

- `SIGN_IDENTITY`
- `SIGNING_CERTIFICATE_P12_BASE64`
- `SIGNING_CERTIFICATE_PASSWORD`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_PASSWORD`

The workflow uploads the DMG as an artifact. It does not create a GitHub Release.
Publish a release only after the second job passes.

## Pinned inputs and licenses

`sources.env` pins the official standalone CPython archives and the official
FFmpeg source archive to SHA256 values. The CPython metadata comes from the
[python-build-standalone release API](https://api.github.com/repos/astral-sh/python-build-standalone/releases/tags/20261001).
The FFmpeg checksum matches the
[Homebrew `ffmpeg@7` recipe](https://github.com/Homebrew/homebrew-core/blob/master/Formula/f/ffmpeg@7.rb).
The build uses that source archive, not Homebrew's GPL-enabled binary.

`Backend/requirements-transkun.lock` pins each package version and its upstream
artifact hashes. Source-only packages build with the tools pinned in
`requirements-build.lock`, with no extra downloads. `collect_licenses.py` copies
each package's license texts and metadata, and fails if any are missing. The
CPython runtime's dependency licenses come from the matching full archive, as the
[standalone distribution docs](https://gregoryszorc.com/docs/python-build-standalone/main/distributions.html)
describe.

A few pinned wheels contain library paths from their build machines.
`relocate_wheel_libraries.py` rewrites only those known paths and re-signs each
changed binary before Python imports it. The bundle includes this script with the
license notices. The pinned hashes describe the original wheels, not the patched
files.

`build_ffmpeg.sh` builds FFmpeg without GPL code, nonfree code, autodetected
external libraries, or network protocols. It enables only the audio decoders,
filters, and WAV and raw float output that the runner uses. The bundle includes
both executables, the LGPL notice, the unmodified source archive, the build
configuration, and the build script. See
[FFmpeg's license guidance](https://ffmpeg.org/legal.html).

`macho_audit.py` rejects any binary that is not arm64, any broken symlink or
symlink that points outside the bundle, and any dependency or rpath outside the
app and the macOS system libraries. A path into the build machine's Homebrew or
toolcache fails the audit.

## Add the benchmark checkpoint

CI sets `DOWNLOAD_BENCHMARK=1`, so CI builds include benchmark V2 and test both
checkpoints. A local build includes it in one of two ways:

- Set `DOWNLOAD_BENCHMARK=1` to run `download_transkun_benchmark_checkpoint.sh`
  during the build.
- Set `TRANSKUN_BENCHMARK_DIR` to a folder that already has `checkpoint.pt` and
  `model.conf`.

Either way, the build checks both files against the hashes in
`Backend/checkpoints.json`. The app never downloads a model at startup.
