import importlib.util
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "seed_internal.py"


def load_module():
    spec = importlib.util.spec_from_file_location("seed_internal_under_test", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class SeedEnvFileTest(unittest.TestCase):
    def test_reads_env_without_overriding(self):
        seed = load_module()
        with tempfile.TemporaryDirectory() as tmp:
            env = Path(tmp) / ".env"
            env.write_text(
                "# 注释\n"
                "\n"
                "VOICE_SEED_EMAIL_DOMAIN=corp.test\n"
                'NEWVOICE_INITIAL_PASSWORD="pass word"\n'
                "export SEED_TEST_EXPORTED='x=1'\n"
                "SEED_TEST_KEEP=from-file\n"
                "not a pair\n",
                encoding="utf-8",
            )
            names = ["VOICE_SEED_EMAIL_DOMAIN", "NEWVOICE_INITIAL_PASSWORD", "SEED_TEST_EXPORTED"]
            with mock.patch.dict(os.environ, {"SEED_TEST_KEEP": "from-env"}):
                for name in names:
                    os.environ.pop(name, None)
                seed.load_env_file(env)
                self.assertEqual(os.environ["VOICE_SEED_EMAIL_DOMAIN"], "corp.test")
                self.assertEqual(os.environ["NEWVOICE_INITIAL_PASSWORD"], "pass word")
                self.assertEqual(os.environ["SEED_TEST_EXPORTED"], "x=1")
                self.assertEqual(os.environ["SEED_TEST_KEEP"], "from-env")

    def test_missing_file_is_ignored(self):
        seed = load_module()
        seed.load_env_file(Path(tempfile.gettempdir()) / "no-such-voice-env")


if __name__ == "__main__":
    unittest.main()
