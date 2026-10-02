#!/usr/bin/env python3
"""Reject Mach-O dependencies that cannot resolve inside this bundle or macOS."""
import argparse
from pathlib import Path
import re
import subprocess
import sys

MAGIC = {b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe",
         b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"}
DYLIB_LOAD_COMMANDS = ("LC_LOAD_DYLIB", "LC_LOAD_WEAK_DYLIB", "LC_REEXPORT_DYLIB",
                      "LC_LOAD_UPWARD_DYLIB", "LC_LAZY_LOAD_DYLIB")


def machos(root: Path) -> list[Path]:
    result = []
    for path in root.rglob("*"):
        if path.is_symlink():
            if not path.resolve().is_relative_to(root) or not path.exists():
                raise ValueError(f"Escaping or broken bundle symlink: {path}")
            continue
        if path.is_file():
            with path.open("rb") as stream:
                if stream.read(4) in MAGIC:
                    result.append(path)
    return sorted(result, key=lambda path: len(path.parts), reverse=True)


def tool(*args: str) -> str:
    return subprocess.run(args, capture_output=True, text=True, check=True).stdout


def command_paths(output: str, command: str) -> list[str]:
    field = "path" if command == "LC_RPATH" else "name"
    pattern = rf"cmd {re.escape(command)}\s+cmdsize \d+\s+{field} (.*?) \(offset"
    return re.findall(pattern, output)


def system_path(path: str) -> bool:
    return path.startswith(("/usr/lib/", "/System/Library/"))


def executable_for(binary: Path, root: Path) -> Path:
    if binary.is_relative_to(root / "Contents/Resources/Backend/python"):
        return root / "Contents/Resources/Backend/python/bin/python3.12"
    if binary.is_relative_to(root / "Contents/Resources/Backend/bin"):
        return binary
    return root / "Contents/MacOS/Piano transcribe"


def expand(value: str, binary: Path, executable: Path) -> Path | None:
    if value.startswith("@loader_path/"):
        return (binary.parent / value.removeprefix("@loader_path/")).resolve()
    if value == "@loader_path":
        return binary.parent
    if value.startswith("@executable_path/"):
        return (executable.parent / value.removeprefix("@executable_path/")).resolve()
    if value == "@executable_path":
        return executable.parent
    if value.startswith("/"):
        return Path(value).resolve()
    return None


def audit(root: Path, binaries: list[Path]) -> None:
    commands = {binary: tool("/usr/bin/otool", "-l", str(binary)) for binary in binaries}
    paths = {binary: command_paths(output, "LC_RPATH") for binary, output in commands.items()}
    errors = []
    for binary in binaries:
        architectures = tool("/usr/bin/lipo", "-archs", str(binary)).split()
        if "arm64" not in architectures:
            errors.append(f"No arm64 slice: {binary.relative_to(root)}")
        executable = executable_for(binary, root)
        contexts = [(binary, value) for value in paths[binary]]
        contexts += [(executable, value) for value in paths.get(executable, [])]
        # Python extension modules can inherit libpython's loader paths.
        libpython = root / "Contents/Resources/Backend/python/lib/libpython3.12.dylib"
        contexts += [(libpython, value) for value in paths.get(libpython, [])]
        for owner, value in contexts:
            resolved = expand(value, owner, executable)
            if resolved is None or (not resolved.is_relative_to(root) and not system_path(str(resolved))):
                errors.append(f"External/unsupported rpath in {binary.relative_to(root)}: {value}")
        # LC_ID_DYLIB names the library itself; it is not a dependency to resolve.
        dependencies = [path for command in DYLIB_LOAD_COMMANDS
                        for path in command_paths(commands[binary], command)]
        for dependency in dependencies:
            if system_path(dependency):
                continue
            candidates = []
            if dependency.startswith("@rpath/"):
                suffix = dependency.removeprefix("@rpath/")
                for owner, value in contexts:
                    directory = expand(value, owner, executable)
                    if directory is not None:
                        candidates.append((directory / suffix).resolve())
            else:
                resolved = expand(dependency, binary, executable)
                if resolved is not None:
                    candidates.append(resolved)
            if not any(system_path(str(path)) or (path.is_relative_to(root) and path.is_file())
                       for path in candidates):
                errors.append(f"Unresolved/external dependency in {binary.relative_to(root)}: {dependency}")
    if errors:
        raise ValueError("\n".join(errors))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("bundle", type=Path)
    parser.add_argument("--list", action="store_true", help="Print deepest-first Mach-O paths, NUL-separated")
    args = parser.parse_args()
    root = args.bundle.resolve()
    if not (root / "Contents").is_dir():
        raise SystemExit("Expected a macOS app bundle.")
    try:
        binaries = machos(root)
        if not binaries:
            raise ValueError("No Mach-O executables in app bundle.")
        if args.list:
            for path in binaries:
                sys.stdout.buffer.write(str(path).encode() + b"\0")
        else:
            audit(root, binaries)
            print(f"Verified {len(binaries)} Mach-O files: arm64 and bundle/system-only dependencies.")
    except ValueError as error:
        raise SystemExit(str(error)) from error


if __name__ == "__main__":
    main()
