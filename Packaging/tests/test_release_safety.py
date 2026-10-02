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
RELOCATION_SPEC = importlib.util.spec_from_file_location("relocate_wheel_libraries", MODULE.with_name("relocate_wheel_libraries.py"))
assert RELOCATION_SPEC and RELOCATION_SPEC.loader
RELOCATION = importlib.util.module_from_spec(RELOCATION_SPEC)
RELOCATION_SPEC.loader.exec_module(RELOCATION)


def load_command(command, path):
    field = "path" if command == "LC_RPATH" else "name"
    return f"cmd {command}\ncmdsize 80\n{field} {path} (offset 12)\n"


class ReleaseSafetyTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = (Path(self.temporary.name) / "Relocated app.app").resolve()
        self.binary = self.root / "Contents/MacOS/Piano transcribe"
        self.binary.parent.mkdir(parents=True)
        self.binary.write_bytes(b"\xcf\xfa\xed\xfe")

    def commands(self, dependency, rpath=None, install_id=None):
        def run(*arguments):
            if arguments[0] == "/usr/bin/lipo":
                return "arm64\n"
            self.assertEqual(arguments[1], "-l")
            output = load_command("LC_LOAD_DYLIB", dependency)
            if rpath:
                output += load_command("LC_RPATH", rpath)
            if install_id:
                output += load_command("LC_ID_DYLIB", install_id)
            return output
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

    def test_library_install_id_is_not_a_load_dependency(self):
        with self.commands("/usr/lib/libSystem.B.dylib", install_id="/opt/llvm-openmp/lib/libomp.dylib"):
            AUDIT.audit(self.root, [self.binary])

    def test_external_load_is_rejected_even_with_an_internal_install_id(self):
        with self.commands("/opt/llvm-openmp/lib/libomp.dylib", install_id="@rpath/libomp.dylib"):
            with self.assertRaisesRegex(ValueError, "external dependency"):
                AUDIT.audit(self.root, [self.binary])


class WheelRelocationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.runtime = Path(self.temporary.name)
        self.packages = self.runtime / "lib/python3.12/site-packages"
        self.outputs = {}
        self.signatures = {}
        for relative, command, original, _ in RELOCATION.REPAIRS:
            binary = self.packages / relative
            binary.parent.mkdir(parents=True, exist_ok=True)
            binary.write_bytes(b"fixture")
            self.outputs[str(binary)] = ("".join(load_command(command, path) for path in original)
                                         + load_command("LC_LOAD_DYLIB", "@loader_path/bundled.dylib"))
            self.signatures[str(binary)] = True

    def commands(self, *arguments):
        if arguments[0] == "/usr/bin/otool":
            return self.outputs[arguments[-1]]
        if arguments[0] == "/usr/bin/codesign":
            self.assertIn(arguments[1:-1], (("--force", "--sign", "-"), ("--verify", "--strict")))
            if arguments[1] == "--force":
                self.signatures[arguments[-1]] = True
            else:
                self.assertTrue(self.signatures[arguments[-1]])
            return ""
        self.assertEqual(arguments[0], "/usr/bin/install_name_tool")
        binary = arguments[-1]
        self.signatures[binary] = False
        if arguments[1] == "-id":
            command = "LC_ID_DYLIB"
            original = AUDIT.command_paths(self.outputs[binary], command)[0]
            replacement = arguments[2]
        elif arguments[1] == "-delete_rpath":
            self.outputs[binary] = self.outputs[binary].replace(load_command("LC_RPATH", arguments[2]), "")
            return ""
        else:
            self.assertEqual(arguments[1], "-rpath")
            command = "LC_RPATH"
            original, replacement = arguments[2:4]
        self.outputs[binary] = self.outputs[binary].replace(load_command(command, original),
                                                          load_command(command, replacement))
        return ""

    def test_only_verified_paths_are_repaired_and_bundled_loads_are_preserved(self):
        with patch.object(RELOCATION.AUDIT, "tool", side_effect=self.commands) as tool:
            RELOCATION.normalize(self.runtime)
            RELOCATION.normalize(self.runtime)
        self.assertEqual(sum(call.args[0] == "/usr/bin/install_name_tool" for call in tool.call_args_list), 8)
        signing = [call.args[1:-1] for call in tool.call_args_list if call.args[0] == "/usr/bin/codesign"]
        self.assertEqual(signing, [("--force", "--sign", "-"), ("--verify", "--strict")] * 6)
        self.assertTrue(all(self.signatures.values()))
        for relative, command, _, replacement in RELOCATION.REPAIRS:
            output = self.outputs[str(self.packages / relative)]
            self.assertEqual(tuple(AUDIT.command_paths(output, command)), replacement)
            self.assertEqual(RELOCATION.dependencies(output), ["@loader_path/bundled.dylib"])

    def test_unexpected_wheel_build_path_is_rejected(self):
        binary = str(self.packages / RELOCATION.REPAIRS[0][0])
        self.outputs[binary] = load_command("LC_ID_DYLIB", "/unexpected/libomp.dylib")
        with patch.object(RELOCATION.AUDIT, "tool", side_effect=self.commands):
            with self.assertRaisesRegex(ValueError, "Unexpected LC_ID_DYLIB"):
                RELOCATION.normalize(self.runtime)


if __name__ == "__main__":
    unittest.main()
