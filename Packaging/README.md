# Packaging And Release Notes

The project is set up so GitHub can own build artifacts and tagged releases.

## Developer DMG

This creates a local unsigned/ad-hoc signed DMG using the existing Transkun
`.venv` plus the separate pc-separation environment/assets:

```bash
./Packaging/build_backend_dev.sh
PYTHON_BIN=python3.10 ./Packaging/build_pc_separation_release.sh
./Packaging/package_dmg.sh --dev-venv-ok --skip-notarize
```

Release packaging also stages the upstream Transkun model-card benchmark
checkpoint. For local testing before packaging, download it with:

```bash
./Packaging/download_transkun_benchmark_checkpoint.sh
```

That writes `checkpoint.pt` and `model.conf` under
`External/transkun-checkpoints/benchmark-v2`.

The developer DMG is useful for validating the app bundle shape, but it is not a
final redistributable release because the staged Python runtime may still depend
on machine-local framework paths.

## Backend Health Check

Use the doctor before spending time on packaging:

```bash
. .venv/bin/activate
python Backend/doctor.py
python Backend/smoke_test.py
./script/app_e2e.sh
```

`doctor.py` verifies Python 3.12, imports `torch` and `transkun`, reports MPS
availability, and detects broken `ffmpeg`/`ffprobe` binaries.

## Optional Piano/Orchestra Separation

The app can run an optional pc-separation pre-step before Transkun. That backend
is intentionally separate from the Transkun runtime because pc-separation has a
different dependency profile.

Release asset setup:

```bash
PYTHON_BIN=python3.10 ./Packaging/build_pc_separation_release.sh
export PIANO_TRANSCRIBE_PC_SEPARATION_ROOT="$PWD/External/pc-separation"
export PIANO_TRANSCRIBE_PC_SEPARATION_PYTHON="$PWD/.pc-separation-env/bin/python"
"$PIANO_TRANSCRIBE_PC_SEPARATION_PYTHON" Backend/pc_separator_smoke_test.py
```

For a quick configuration check:

```bash
"$PIANO_TRANSCRIBE_PC_SEPARATION_PYTHON" Backend/pc_separator_runner.py \
  --doctor \
  --repo "$PIANO_TRANSCRIBE_PC_SEPARATION_ROOT"
```

The release packaging path stages only the HDMC separator source/config and
`checkpoints/HDMC20_R_H_HU_HUS/hdemucs_best.pth` into the app bundle. The
script writes SHA256 and provenance notes next to the staged upstream checkout.

App E2E with the separator enabled:

```bash
PIANO_TRANSCRIBE_TEST_SEPARATOR=1 \
PIANO_TRANSCRIBE_PC_SEPARATION_ROOT="$PWD/External/pc-separation" \
PIANO_TRANSCRIBE_PC_SEPARATION_PYTHON="$PWD/.pc-separation-env/bin/python" \
./script/app_e2e.sh
```

## Public Release Requirements

Before public release:

- Replace the developer `.venv` backend staging with a standalone Python 3.12 runtime.
- Replace the developer `.pc-separation-env` staging with a standalone Python 3.10 runtime.
- Bundle a vetted LGPL-compatible `ffmpeg` and `ffprobe` build.
- Complete `Contents/Resources/Backend/licenses`.
- Sign every nested executable and dynamic library.
- Sign the app with a Developer ID Application certificate.
- Notarize the DMG.

## Signing

Set the signing identity before packaging:

```bash
export SIGN_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)"
export DEVELOPMENT_TEAM="TEAMID"
```

Check an app bundle before distribution:

```bash
./Packaging/check_release_readiness.sh "build/DerivedData/Build/Products/Release/Piano transcribe.app"
```

## Notarization

Set Apple notarization credentials:

```bash
export APPLE_ID="you@example.com"
export APPLE_TEAM_ID="TEAMID"
export APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"
```

Then run:

```bash
./Packaging/package_dmg.sh --dev-venv-ok
```

For the final release, remove `--dev-venv-ok` after the standalone runtime flows
for both Transkun and pc-separation are implemented.
