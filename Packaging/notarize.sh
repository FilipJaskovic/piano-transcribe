#!/usr/bin/env bash
set -euo pipefail

ARTIFACT="${1:-}"

if [[ -z "$ARTIFACT" || ! -f "$ARTIFACT" ]]; then
  echo "usage: $0 <artifact.dmg|artifact.zip>" >&2
  exit 2
fi

if [[ -z "${APPLE_ID:-}" || -z "${APPLE_TEAM_ID:-}" || -z "${APPLE_APP_PASSWORD:-}" ]]; then
  cat >&2 <<'MESSAGE'
Missing notarization credentials.

Set:
  APPLE_ID
  APPLE_TEAM_ID
  APPLE_APP_PASSWORD
MESSAGE
  exit 1
fi

xcrun notarytool submit "$ARTIFACT" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_PASSWORD" \
  --wait

xcrun stapler staple "$ARTIFACT"
spctl --assess --type open --verbose=4 "$ARTIFACT"
