#!/usr/bin/env bash
set -euo pipefail
# CI-only temporary keychain. Never run this against a developer's daily keychain.
[[ "${GITHUB_ACTIONS:-}" == true ]] || { echo 'This helper is for GitHub Actions only.' >&2; exit 1; }
: "${SIGNING_CERTIFICATE_P12_BASE64:?Signing certificate required}" "${SIGNING_CERTIFICATE_PASSWORD:?Certificate password required}" \
  "${SIGN_IDENTITY:?Developer ID identity required}" "${APPLE_ID:?Apple ID required}" \
  "${APPLE_TEAM_ID:?Apple team required}" "${APPLE_APP_PASSWORD:?App-specific password required}"
umask 077
CERTIFICATE="$RUNNER_TEMP/signing.p12"
KEYCHAIN="$RUNNER_TEMP/piano-transcribe-signing.keychain-db"
PASSWORD="$(uuidgen)"
echo "::add-mask::$PASSWORD"
trap 'rm -f "$CERTIFICATE"' EXIT
printf '%s' "$SIGNING_CERTIFICATE_P12_BASE64" | base64 -D > "$CERTIFICATE"
security create-keychain -p "$PASSWORD" "$KEYCHAIN"
printf 'SIGNING_KEYCHAIN=%s\n' "$KEYCHAIN" >> "$GITHUB_ENV"
security set-keychain-settings -lut 7200 "$KEYCHAIN"
security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"
security import "$CERTIFICATE" -P "$SIGNING_CERTIFICATE_PASSWORD" -k "$KEYCHAIN" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASSWORD" "$KEYCHAIN"
security list-keychains -d user -s "$KEYCHAIN" "$(security default-keychain -d user | tr -d '"' | xargs)"
security find-identity -v -p codesigning "$KEYCHAIN" | grep -F "$SIGN_IDENTITY" > /dev/null
