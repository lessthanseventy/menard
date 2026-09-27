"""What each arm loads: `all` is all of menard, the hooks and manos' tools; A is none of it."""

import json
import os
import subprocess
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
    def test_all_loads_menard_and_manos(self):
        # riverside1 ran `all` without manos, the MCP tools, from a list kept apart from it (2026-09-26)
        self.assertEqual(plugin_dirs("all"), [str(run.PLUGINS / "all"), str(run.PLUGINS / "all" / "manos")])

    def test_a_loads_nothing(self):
        self.assertEqual(plugin_dirs("A"), [])

    def test_all_guards_an_edit_of_a_module(self):
        # the guard left the shipped plugin in 69059a4; `all` is all of menard, so it has it: an Edit
        # or Write of a module is refused toward the verbs (riverside1: 38 shell edits, no verb)
        with tempfile.TemporaryDirectory() as tmp, unittest.mock.patch.object(run, "PLUGINS", Path(tmp)):
            run.build_plugins(force=True)
            root = Path(tmp) / "all"
            hooks = json.loads((root / "hooks" / "hooks.json").read_text())["hooks"]["PreToolUse"]
            guard = [e for e in hooks if e.get("matcher") == "Edit|MultiEdit|Write|NotebookEdit"]
            self.assertEqual(len(guard), 1)

            module = Path(tmp) / "m.ex"
            module.write_text("defmodule M do\n  def go, do: 1\nend\n")
            payload = {"tool_name": "Edit", "tool_input": {"file_path": str(module), "old_string": "1", "new_string": "2"}}
            script = guard[0]["hooks"][0]["command"].replace("${CLAUDE_PLUGIN_ROOT}", str(root))
            # the repo's own menard and its build, not a second one compiled into the copy
            (root / "bin" / "menard").unlink()
            (root / "bin" / "menard").symlink_to(run.REPO / "bin" / "menard")
            done = subprocess.run(["bash", "-c", script], input=json.dumps(payload), capture_output=True, text=True,
                                  env={**os.environ, "CLAUDE_PLUGIN_ROOT": str(root)})
            self.assertEqual(done.returncode, 2, done.stderr)
            self.assertIn("mcp__plugin_manos_menard__", done.stderr)


if __name__ == "__main__":
    unittest.main()
