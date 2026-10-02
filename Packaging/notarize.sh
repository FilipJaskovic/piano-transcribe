#!/usr/bin/env bash
set -euo pipefail
ARTIFACT="${1:?App bundle or DMG required}"
: "${APPLE_ID:?Apple ID required}" "${APPLE_TEAM_ID:?Apple team required}" "${APPLE_APP_PASSWORD:?App-specific password required}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
SUBMISSION="$ARTIFACT"
if [[ -d "$ARTIFACT/Contents" ]]; then
  SUBMISSION="$WORK/application.zip"
  ditto -c -k --keepParent "$ARTIFACT" "$SUBMISSION"
elif [[ ! -f "$ARTIFACT" ]]; then
  echo 'Notarization artifact does not exist.' >&2
  exit 2
fi
xcrun notarytool submit "$SUBMISSION" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_PASSWORD" --wait --output-format json > "$WORK/result.json"
STATUS="$(/usr/bin/plutil -extract status raw -o - "$WORK/result.json")"
if [[ "$STATUS" != 'Accepted' ]]; then
  cat "$WORK/result.json" >&2
  echo 'Apple did not accept the notarization submission.' >&2
  exit 1
fi
xcrun stapler staple "$ARTIFACT"
xcrun stapler validate "$ARTIFACT"
if [[ -d "$ARTIFACT/Contents" ]]; then
  spctl --assess --type execute --verbose=4 "$ARTIFACT"
else
  spctl --assess --type open --context context:primary-signature --verbose=4 "$ARTIFACT"
fi
