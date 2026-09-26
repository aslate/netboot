import importlib.util
import tempfile
import unittest
from pathlib import Path


SOURCE = Path(__file__).resolve().parents[1] / "scripts/render-netboot-config.py"
SPEC = importlib.util.spec_from_file_location("render_netboot_config", SOURCE)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class RendererTests(unittest.TestCase):
    def test_substitution_is_literal_and_does_not_execute_shell_text(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            template = root / "template"
            output = root / "generated"
            template.write_text("value=${SAFE}\n", encoding="utf-8")
            MODULE.render(template, output, {"SAFE": "$(touch SHOULD_NOT_EXIST)"})
            self.assertEqual(output.read_text(encoding="utf-8"), "value=$(touch SHOULD_NOT_EXIST)\n")
            self.assertFalse((root / "SHOULD_NOT_EXIST").exists())

    def test_unknown_placeholder_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            template = root / "template"
            template.write_text("${MISSING}\n", encoding="utf-8")
            with self.assertRaises(ValueError):
                MODULE.render(template, root / "generated", {})

    def test_environment_rejects_shell_syntax(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "netboot.env"
            path.write_text("NETBOOT_INTERFACE=$(id)\n", encoding="utf-8")
            with self.assertRaises(ValueError):
                MODULE.read_env(path)


if __name__ == "__main__":
    unittest.main()
