import importlib.util
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "pdfseal_installer", Path(__file__).resolve().parent.parent / "scripts/install.py"
)
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class DiscoveryTests(unittest.TestCase):
    def test_waits_for_discovery_before_enabling(self):
        responses = [
            SimpleNamespace(returncode=0),
            SimpleNamespace(stdout="[]"),
            SimpleNamespace(stdout='[{"id":"arkane.pdfseal"}]'),
            SimpleNamespace(returncode=0),
        ]
        with patch.object(installer.subprocess, "run", side_effect=responses) as run, \
                patch.object(installer.time, "sleep") as sleep:
            installer.enable_plugin()
        self.assertEqual(run.call_count, 4)
        sleep.assert_called_once_with(0.2)
        self.assertEqual(run.call_args.args[0], ["omarchy", "plugin", "enable", "arkane.pdfseal"])

    def test_timeout_leaves_files_installed_without_enabling_unknown_plugin(self):
        with patch.object(installer.subprocess, "run") as run, \
                patch.object(installer.time, "monotonic", side_effect=[0, 16]):
            with self.assertRaisesRegex(RuntimeError, "PDFSeal was installed"):
                installer.enable_plugin()
        self.assertEqual(run.call_count, 1)


if __name__ == "__main__":
    unittest.main()
