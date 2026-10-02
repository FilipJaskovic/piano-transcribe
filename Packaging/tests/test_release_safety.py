"""Focused checks for the release gate's external-library rejection."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

MODULE = Path(__file__).resolve().parents[1] / "macho_audit.py"
SPEC = importlib.util.spec_from_file_location("macho_audit", MODULE)
assert SPEC and SPEC.loader
AUDIT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUDIT)


class ReleaseSafetyTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = (Path(self.temporary.name) / "Relocated app.app").resolve()
        self.binary = self.root / "Contents/MacOS/Piano transcribe"
        self.binary.parent.mkdir(parents=True)
        self.binary.write_bytes(b"\xcf\xfa\xed\xfe")

    def commands(self, dependency, rpath=None):
        def run(*arguments):
            if arguments[0] == "/usr/bin/lipo":
                return "arm64\n"
            if arguments[1] == "-l":
                return f"cmd LC_RPATH\ncmdsize 40\npath {rpath} (offset 12)\n" if rpath else ""
            return f"binary:\n\t{dependency} (compatibility version 1.0.0, current version 1.0.0)\n"
        return patch.object(AUDIT, "tool", side_effect=run)

    def test_system_libraries_need_not_exist_outside_dyld_cache(self):
        with self.commands("/usr/lib/libSystem.B.dylib"):
            AUDIT.audit(self.root, [self.binary])

    def test_homebrew_dependency_is_rejected(self):
        with self.commands("/opt/homebrew/Cellar/python@3.12/Python"):
            with self.assertRaisesRegex(ValueError, "external dependency"):
                AUDIT.audit(self.root, [self.binary])

    def test_loader_relative_library_resolves_after_relocation(self):
        library = self.root / "Contents/Frameworks/library.dylib"
        library.parent.mkdir()
        library.write_bytes(b"fixture")
        with self.commands("@rpath/library.dylib", "@loader_path/../Frameworks"):
            AUDIT.audit(self.root, [self.binary])

    def test_escaping_symlink_is_rejected(self):
        (self.root / "external").symlink_to("/opt/homebrew")
        with self.assertRaisesRegex(ValueError, "Escaping or broken"):
            AUDIT.machos(self.root)

    def test_external_rpath_is_rejected_even_for_system_only_binary(self):
        with self.commands("/usr/lib/libSystem.B.dylib", "/Users/developer/python/lib"):
            with self.assertRaisesRegex(ValueError, "External/unsupported rpath"):
                AUDIT.audit(self.root, [self.binary])


if __name__ == "__main__":
    unittest.main()
