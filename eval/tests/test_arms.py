"""What each arm loads: `all` is all of menard, the hooks and manos' tools; A is none of it."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import run  # noqa: E402


def plugin_dirs(arm):
    cmd = run.claude_cmd("p", "m", arm)
    return [cmd[i + 1] for i, a in enumerate(cmd) if a == "--plugin-dir"]


class Arms(unittest.TestCase):
    def test_all_loads_menard_and_manos(self):
        # riverside1 ran `all` without manos, the MCP tools, from a list kept apart from it (2026-09-26)
        self.assertEqual(plugin_dirs("all"), [str(run.PLUGINS / "all"), str(run.PLUGINS / "all" / "manos")])

    def test_a_loads_nothing(self):
        self.assertEqual(plugin_dirs("A"), [])


if __name__ == "__main__":
    unittest.main()
