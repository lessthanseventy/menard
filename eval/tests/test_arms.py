"""What each arm loads: `with` is the menard plugin as shipped, `without` is none of it."""

import json
import sys
import tempfile
import unittest
import unittest.mock
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import run  # noqa: E402


def plugin_dirs(arm):
    cmd = run.claude_cmd("p", "m", arm)
    return [cmd[i + 1] for i, a in enumerate(cmd) if a == "--plugin-dir"]


class Arms(unittest.TestCase):
    def test_with_loads_the_one_plugin(self):
        self.assertEqual(plugin_dirs("with"), [str(run.PLUGINS / "with")])

    def test_without_loads_nothing(self):
        self.assertEqual(plugin_dirs("without"), [])

    def test_there_are_two_arms_and_no_other_is_run(self):
        self.assertEqual(run.ARMS, ("without", "with"))
        with unittest.mock.patch.object(sys, "argv", ["run.py", "r", "--arms", "without,all"]):
            with self.assertRaises(SystemExit) as refused:
                run.main()
        self.assertIn("no arm all", str(refused.exception))

    def test_the_plugin_is_the_repo_as_shipped(self):
        # riverside1 ran `all` on a plugin the runner had rewritten, from a list kept apart from the
        # shipped one (2026-09-26): what is measured is what a user installs, byte for byte
        with tempfile.TemporaryDirectory() as tmp, unittest.mock.patch.object(run, "PLUGINS", Path(tmp)):
            run.build_plugins(force=True)
            root = Path(tmp) / "with"
            for shipped in [".claude-plugin/plugin.json", "hooks/hooks.json", "skills/menard/SKILL.md", "bin/menard"]:
                self.assertEqual((root / shipped).read_bytes(), (run.REPO / shipped).read_bytes(), shipped)
            manifest = json.loads((root / ".claude-plugin/plugin.json").read_text())
            self.assertEqual(list(manifest["mcpServers"]), ["menard"])


if __name__ == "__main__":
    unittest.main()
