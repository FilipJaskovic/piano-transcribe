#!/usr/bin/env bash
set -euo pipefail

URL="${1:?URL required}"
EXPECTED="${2:?Expected SHA256 required}"
DEST="${3:?Destination required}"
[[ "$EXPECTED" =~ ^[a-f0-9]{64}$ ]] || { echo 'Invalid expected SHA256.' >&2; exit 2; }
mkdir -p "$(dirname "$DEST")"
verify() { [[ "$(shasum -a 256 "$1" | awk '{print $1}')" == "$EXPECTED" ]]; }
if [[ -f "$DEST" ]] && verify "$DEST"; then
  exit 0
fi
TEMP="$(mktemp "${DEST}.XXXXXX")"
trap 'rm -f "$TEMP"' EXIT
curl --fail --location --retry 3 --proto '=https' --tlsv1.2 "$URL" --output "$TEMP"
verify "$TEMP" || { echo "Checksum mismatch: $URL" >&2; exit 1; }
mv "$TEMP" "$DEST"
