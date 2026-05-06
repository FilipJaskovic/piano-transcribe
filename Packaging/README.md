# Packaging And Release Notes

The project is set up so GitHub can own build artifacts and tagged releases.

## Developer DMG

This creates a local unsigned/ad-hoc signed DMG using the existing `.venv`:

```bash
./Packaging/build_backend_dev.sh
./Packaging/package_dmg.sh --dev-venv-ok --skip-notarize
```

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
is intentionally separate from the Transkun venv because pc-separation has an
older dependency profile.

Developer setup:

```bash
./Packaging/build_pc_separation_dev.sh --download-weights
export PIANO_TRANSCRIBE_PC_SEPARATION_ROOT="$PWD/External/pc-separation"
export PIANO_TRANSCRIBE_PC_SEPARATION_PYTHON="$PWD/.pc-separation-env/bin/python"
./script/build_and_run.sh
```

For a quick configuration check:

```bash
"$PIANO_TRANSCRIBE_PC_SEPARATION_PYTHON" Backend/pc_separator_runner.py \
  --doctor \
  --repo "$PIANO_TRANSCRIBE_PC_SEPARATION_ROOT"
```

The release app still needs a packaged pc-separation runtime and pretrained
weights before this feature is redistributable.

## Public Release Requirements

Before public release:

- Replace the developer `.venv` backend staging with a standalone Python 3.12 runtime.
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

For the final release, remove `--dev-venv-ok` after the standalone runtime flow
is implemented.
