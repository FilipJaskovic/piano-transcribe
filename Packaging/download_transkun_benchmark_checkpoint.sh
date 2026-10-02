#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PYTHON="${PYTHON_BIN:-$ROOT_DIR/build/Backend/python/bin/python3.12}"
DEST="${DEST_DIR:-$ROOT_DIR/External/transkun-checkpoints/benchmark-v2}"
[[ -x "$PYTHON" ]] || { echo 'Prepare the standalone backend first, or set PYTHON_BIN.' >&2; exit 1; }
"$PYTHON" -I -B - "$ROOT_DIR/Backend/checkpoints.json" "$DEST" <<'PY'
import hashlib
import json
from pathlib import Path
import shutil
import sys
import tempfile
import urllib.request
import zipfile

manifest = json.loads(Path(sys.argv[1]).read_text())["benchmark-v2"]
destination = Path(sys.argv[2]).resolve()
source = 'https://drive.usercontent.google.com/download?id=1pxGpO8eCdFxMRrXi_YUh7_uC0Ae26coB&export=download&confirm=t'
def valid_existing():
    for kind in ('weight', 'config'):
        path = destination / manifest[kind]
        if not path.is_file():
            return False
        with path.open('rb') as stream:
            if hashlib.file_digest(stream, 'sha256').hexdigest() != manifest[kind + 'SHA256']:
                return False
    return True
if valid_existing():
    print('Verified cached benchmark checkpoint:', destination)
    sys.exit(0)
with tempfile.TemporaryDirectory() as work:
    temporary = Path(work)
    archive = temporary / 'checkpoint.zip'
    with urllib.request.urlopen(source, timeout=120) as response, archive.open('wb') as output:
        shutil.copyfileobj(response, output)
    with zipfile.ZipFile(archive) as container:
        for kind in ('weight', 'config'):
            name = manifest[kind]
            path = temporary / name
            # Read only the two expected members; never extract arbitrary archive paths.
            with container.open('checkpointMSimpler/' + name) as member, path.open('wb') as output:
                shutil.copyfileobj(member, output)
            with path.open('rb') as stream:
                actual = hashlib.file_digest(stream, 'sha256').hexdigest()
            if actual != manifest[kind + 'SHA256']:
                raise SystemExit('Downloaded benchmark ' + kind + ' failed its committed checksum.')
    destination.mkdir(parents=True, exist_ok=True)
    for kind in ('weight', 'config'):
        shutil.copyfile(temporary / manifest[kind], destination / manifest[kind])
    (destination / 'SOURCE.json').write_text(json.dumps(manifest, indent=2) + '\n')
print('Verified benchmark checkpoint:', destination)
PY
