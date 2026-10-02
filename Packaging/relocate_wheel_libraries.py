#!/usr/bin/env python3
"""Repair verified build-machine paths in pinned release wheels.

The lockfile hashes attest downloaded archives, not these modified binary bytes.
This recipe preserves load dependencies and re-signs changed files ad-hoc before
the distribution's final signing step.
"""
import argparse
import importlib.metadata
import importlib.util
from pathlib import Path
import sys

SPEC = importlib.util.spec_from_file_location("macho_audit", Path(__file__).with_name("macho_audit.py"))
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("The Mach-O inspection helper is missing.")
AUDIT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUDIT)

TORCHAUDIO_BUILD_RPATH = "/Users/ec2-user/runner/_work/_temp/conda_environment_23408961961/lib"
REPAIRS = (
    ("torch/lib/libomp.dylib", "LC_ID_DYLIB", ("/opt/llvm-openmp/lib/libomp.dylib",), ("@rpath/libomp.dylib",)),
    ("torchaudio/.dylibs/libc++.1.0.dylib", "LC_ID_DYLIB",
     ("/DLC/torchaudio/.dylibs/libc++.1.0.dylib",), ("@rpath/libc++.1.0.dylib",)),
    ("torchaudio/lib/_torchaudio.abi3.so", "LC_RPATH", (TORCHAUDIO_BUILD_RPATH,),
     ("@loader_path/../../torch/lib",)),
    ("torchaudio/lib/libtorchaudio.abi3.so", "LC_RPATH", (TORCHAUDIO_BUILD_RPATH,),
     ("@loader_path/../../torch/lib",)),
    ("PIL/.dylibs/libjpeg.62.4.0.dylib", "LC_RPATH",
     ("/Users/runner/work/Pillow/Pillow/build/deps/darwin/lib",), ()),
    ("scipy/linalg/_fblas.cpython-312-darwin.so", "LC_RPATH", (
        "@loader_path",
        "/opt/homebrew/Cellar/gcc@13/13.4.0/lib/gcc/13/gcc/aarch64-apple-darwin23/13",
        "/opt/homebrew/Cellar/gcc@13/13.4.0/lib/gcc/13/gcc",
        "/opt/homebrew/Cellar/gcc@13/13.4.0/lib/gcc/13",
    ), ("@loader_path",)),
)


def dependencies(output: str) -> list[str]:
    return [path for command in AUDIT.DYLIB_LOAD_COMMANDS for path in AUDIT.command_paths(output, command)]


def normalize(runtime: Path) -> None:
    packages = runtime / "lib/python3.12/site-packages"
    for relative, command, original, replacement in REPAIRS:
        binary = packages / relative
        if not binary.is_file():
            raise ValueError(f"Pinned wheel library missing: {relative}")
        before = AUDIT.tool("/usr/bin/otool", "-l", str(binary))
        paths = tuple(AUDIT.command_paths(before, command))
        if paths == replacement:
            continue
        if paths != original:
            raise ValueError(f"Unexpected {command} in pinned wheel library {relative}: {paths}")
        if command == "LC_ID_DYLIB":
            AUDIT.tool("/usr/bin/install_name_tool", "-id", replacement[0], str(binary))
        elif len(original) == len(replacement) == 1:
            AUDIT.tool("/usr/bin/install_name_tool", "-rpath", original[0], replacement[0], str(binary))
        else:
            for path in original:
                if path not in replacement:
                    AUDIT.tool("/usr/bin/install_name_tool", "-delete_rpath", path, str(binary))
        # Apple Silicon rejects mutated upstream signatures before later bundle signing.
        AUDIT.tool("/usr/bin/codesign", "--force", "--sign", "-", str(binary))
        AUDIT.tool("/usr/bin/codesign", "--verify", "--strict", str(binary))
        after = AUDIT.tool("/usr/bin/otool", "-l", str(binary))
        if tuple(AUDIT.command_paths(after, command)) != replacement or dependencies(before) != dependencies(after):
            raise ValueError(f"Wheel relocation changed unexpected load commands: {relative}")
    print("Normalized pinned wheel library IDs and bundle-relative loader paths.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("runtime", type=Path)
    root = parser.parse_args().runtime.resolve()
    if sys.version_info[:2] != (3, 12) or Path(sys.prefix).resolve() != root:
        raise SystemExit("Wheel relocation must use the staged Python 3.12 runtime.")
    for name, version in (("torch", "2.11.0"), ("torchaudio", "2.11.0"), ("pillow", "12.2.0"), ("scipy", "1.17.1")):
        if importlib.metadata.version(name) != version:
            raise SystemExit(f"Wheel relocation requires the pinned {name} {version} wheel.")
    try:
        normalize(root)
    except ValueError as error:
        raise SystemExit(str(error)) from error


if __name__ == "__main__":
    main()
