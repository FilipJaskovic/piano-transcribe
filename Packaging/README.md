# Packaging Piano transcribe V2

V2 release artifacts target Apple Silicon and macOS 26 or later. The app bundles
Transkun, its packaged-default and existing benchmark checkpoints, CPython 3.12, and local-only FFmpeg and
ffprobe. There is no separator, user-installed Python, Homebrew requirement, or
first-run model download.

## Build an unsigned testing artifact

Run on an Apple Silicon Mac with Xcode 26 and at least 8 GiB free:

```bash
./Packaging/package_dmg.sh --allow-unsigned
```

The filename includes `-unsigned`. It is ad-hoc signed for local executable
integrity, not Developer ID signed or notarized. Do not describe this channel as
Gatekeeper-ready. No Developer ID certificate is needed for this explicit mode.

## Build a notarized artifact

Set `SIGN_IDENTITY` to a Developer ID Application identity and provide `APPLE_ID`,
`APPLE_TEAM_ID`, and `APPLE_APP_PASSWORD`. The certificate must already be
installed locally. Then run:

```bash
./Packaging/package_dmg.sh
```

Missing identity or credentials fail before backend downloads. The pipeline signs
nested Mach-O files individually, signs the app, requires Apple's `Accepted`
notarization result, staples and validates both the app and final DMG, and checks
Gatekeeper. `VERSION` defaults to `2.0.0`; `BUILD_NUMBER` defaults to `2`.

## GitHub Actions

Pull requests and main pushes run focused tests and build the Swift app. Manual
runs and version tags also build the standalone backend and DMG, then download
that artifact in a separate job with no source checkout or Python setup. The
consumer relocates the app and runs bundle validation and E2E with networking
denied. Production requires these repository secrets:

- `SIGN_IDENTITY`
- `SIGNING_CERTIFICATE_P12_BASE64`
- `SIGNING_CERTIFICATE_PASSWORD`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_PASSWORD`

A manual run can explicitly select `allow_unsigned`. Version tags cannot silently
fall back to unsigned packaging. Workflows upload candidate artifacts; they do
not automatically create or publish a GitHub Release. Publish only after the
independent consumer passes and a human authorizes the release.

## Pinned inputs and licenses

`sources.env` pins official standalone CPython archives and the official FFmpeg
source archive to expected SHA256 values. Runtime metadata comes from the
[official standalone release API](https://api.github.com/repos/astral-sh/python-build-standalone/releases/tags/20261001).
The FFmpeg source checksum was cross-checked against the maintained
[Homebrew source recipe](https://github.com/Homebrew/homebrew-core/blob/master/Formula/f/ffmpeg@7.rb);
we build from that source, not Homebrew's GPL-enabled binary.

`Backend/requirements-transkun.lock` locks distribution versions and upstream
artifact hashes. Source-only Python packages use the separately pinned build
tools without dynamic build-isolation downloads. The pinned standalone runtime
supplies the fixed pip version. Package legal texts and metadata are collected
from the installed distributions; missing evidence fails collection. Runtime
dependency licenses and metadata are copied from the matching full Python
archive, following the [standalone archive documentation](https://gregoryszorc.com/docs/python-build-standalone/main/distributions.html).

The pinned wheels contain a few build-machine library paths. A narrow relocation
recipe repairs only the verified paths, preserves actual library loads, and
re-signs changed binaries before runtime imports. The recipe is included with
license notices; download hashes describe the original wheels, not patched bytes.

FFmpeg is built without GPL, nonfree, external autodetected libraries or network
protocols. It includes only the audio decoders, filters and WAV/raw-float output
needed by the runner. Both executables, the LGPL notice, unmodified source
archive, build configuration and recipe are bundled. See
[FFmpeg's licensing guidance](https://ffmpeg.org/legal.html).

`macho_audit.py` rejects non-arm64 binaries, broken/escaping symlinks, and
unresolved dependencies or rpaths outside the app and macOS system libraries.
This prevents builder Homebrew/toolcache paths from masquerading as portability.

## Optional existing benchmark checkpoint

The packaged-default model remains the default. Production CI bundles the existing
benchmark V2 option with `DOWNLOAD_BENCHMARK=1` and tests both selections. For local
builds, a benchmark V2 pair can be supplied with `TRANSKUN_BENCHMARK_DIR`; staging verifies both files against
`Backend/checkpoints.json`. To fetch that existing upstream checkpoint at build
time, run `download_transkun_benchmark_checkpoint.sh`. It validates the committed
weight/config hashes before accepting files. No application startup downloads
are performed.

## Verification limits

Writing these scripts or running focused tests does not establish release
readiness. The full standalone build, independent relocated offline E2E, and
selected signing/notarization path must run successfully on the final artifact.
