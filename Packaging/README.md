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
