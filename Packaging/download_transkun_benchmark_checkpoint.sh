#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-$ROOT_DIR/.venv/bin/python}"
DEST_DIR="${DEST_DIR:-$ROOT_DIR/External/transkun-checkpoints/benchmark-v2}"
FILE_ID="${TRANSKUN_BENCHMARK_V2_FILE_ID:-1pxGpO8eCdFxMRrXi_YUh7_uC0Ae26coB}"
SOURCE_URL="https://drive.google.com/file/d/$FILE_ID/view?usp=drive_link"

if [[ ! -x "$PYTHON_BIN" ]]; then
  echo "Missing Python executable: $PYTHON_BIN" >&2
  echo "Run ./Packaging/build_backend_dev.sh first, or set PYTHON_BIN." >&2
  exit 1
fi

"$PYTHON_BIN" - "$DEST_DIR" "$FILE_ID" "$SOURCE_URL" <<'PY'
from pathlib import Path
import hashlib
import subprocess
import sys
import tempfile
import zipfile

dest = Path(sys.argv[1]).resolve()
file_id = sys.argv[2]
source_url = sys.argv[3]

try:
    import gdown
except ImportError:
    subprocess.check_call([sys.executable, "-m", "pip", "install", "gdown"])
    import gdown

with tempfile.TemporaryDirectory() as tmp_dir:
    tmp = Path(tmp_dir)
    archive = tmp / "checkpointTransformer.zip"
    result = gdown.download(id=file_id, output=str(archive), quiet=False)
    if result is None or not archive.exists():
        raise RuntimeError("Could not download Transkun benchmark checkpoint.")

    with zipfile.ZipFile(archive) as zf:
        zf.extractall(tmp)

    source = tmp / "checkpointMSimpler"
    weight = source / "checkpoint.pt"
    conf = source / "model.conf"
    if not weight.exists() or not conf.exists():
        raise RuntimeError("Downloaded benchmark checkpoint did not contain checkpoint.pt and model.conf.")

    dest.mkdir(parents=True, exist_ok=True)
    (dest / "checkpoint.pt").write_bytes(weight.read_bytes())
    (dest / "model.conf").write_bytes(conf.read_bytes())

def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

lines = []
for name in ["checkpoint.pt", "model.conf"]:
    path = dest / name
    lines.append(f"{sha256(path)}  {name}\n")
(dest / "SHA256SUMS").write_text("".join(lines), encoding="utf-8")

(dest / "SOURCE.md").write_text(
    "# Transkun Benchmark V2 Checkpoint\n\n"
    f"Source: {source_url}\n"
    f"Google Drive file ID: `{file_id}`\n\n"
    "This is the Transkun V2 checkpoint linked from the upstream Transkun "
    "README model card table as `Transkun V2`.\n",
    encoding="utf-8",
)

print(f"Transkun benchmark checkpoint ready: {dest}")
PY
