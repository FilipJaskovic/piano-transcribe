#!/usr/bin/env python3
"""Copy installed distribution notices and fail when license evidence is missing."""
from importlib.metadata import distributions
import json
from pathlib import Path
import shutil
import sys


def main() -> None:
    destination = Path(sys.argv[1]).resolve()
    packages = destination / "python-packages"
    packages.mkdir(parents=True, exist_ok=True)
    records = []
    missing = []
    for distribution in sorted(distributions(), key=lambda item: item.metadata["Name"].lower()):
        name = distribution.metadata["Name"]
        target = packages / f"{name}-{distribution.version}"
        target.mkdir(exist_ok=True)
        notices = []
        for relative in distribution.files or []:
            filename = Path(str(relative)).name.lower()
            if not filename.startswith(("license", "licence", "copying", "notice", "copyright", "authors")):
                continue
            source = Path(distribution.locate_file(relative))
            if source.is_file():
                # Preserve paths so vendored dependencies' similarly named notices do not collide.
                output = target / str(relative).replace("../", "parent/")
                output.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, output)
                notices.append(str(output.relative_to(destination)))
        if name.lower().replace("_", "-") == "tensorboard-data-server" and not notices:
            source = destination / "tensorboard-data-server-LICENSE"
            if source.is_file():
                shutil.copyfile(source, target / "LICENSE")
                notices.append(str((target / "LICENSE").relative_to(destination)))
        metadata = distribution.read_text("METADATA") or ""
        (target / "METADATA").write_text(metadata, encoding="utf-8")
        records.append({
            "name": name, "version": distribution.version,
            "license": distribution.metadata.get("License-Expression") or distribution.metadata.get("License"),
            "project_urls": distribution.metadata.get_all("Project-URL") or [],
            "notices": notices,
        })
        if not notices:
            missing.append(f"{name}=={distribution.version}")
    (destination / "PYTHON-PACKAGES.json").write_text(json.dumps(records, indent=2) + "\n", encoding="utf-8")
    if missing:
        raise SystemExit("Missing upstream license texts: " + ", ".join(missing))
    print(f"Collected legal texts for {len(records)} Python distributions.")


if __name__ == "__main__":
    main()
