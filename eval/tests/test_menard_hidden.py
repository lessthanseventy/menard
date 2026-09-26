"""Arm A must not learn menard exists: no door to it and no passage about it, in a real workspace.

Needs the Tlön template (MENARD_EVAL_WORK, default /tmp/menard-eval-tlon); skipped without it.
"""

import os
import shutil
import subprocess
import sys
import unittest
import unittest.mock
from pathlib import Path

EVAL = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(EVAL))
import run  # noqa: E402

# set here, not through run's import: another test module may have imported run first
WORK = Path(os.environ.get("MENARD_EVAL_WORK", "/tmp/menard-eval-tlon"))

CASE = EVAL / "tlon" / "cases" / "focus3"

# Tlön's product, the same in every arm, and no way to menard (hide_menard.py's docstring):
# the library dependency and the code that calls it, and test data naming a sibling project.
ALLOWED = {
    "server/mix.exs": "the dependency line itself",
    "server/mix.lock": "the dependency's pin",
    "console/mix.lock": "the dependency's pin (console reads the server's lock)",
    "server/lib/server/source/tools.ex": "Tlön's coworker source verbs call the library",
    "server/lib/server/mcp/tools/source.ex": "the MCP tools that expose those verbs",
    "console/lib/mix/tasks/console.seed.ex": "seed data: a sibling project's name",
    "console/test/console/panel/picker_test.exs": "test data: a thread title",
    "console/test/console/picker_test.exs": "test data: a thread title",
    "server/test/fixtures/panes/pi_permission_prompt.txt": "a captured pane from a real session",
    "server/test/server/bootstrap_test.exs": "test data: a project name",
    "server/test/server/channel_test.exs": "test data: an agent name",
    "server/test/server/mcp/server_test.exs": "test data",
    "server/test/server/projects_test.exs": "test data: a project name",
    "server/test/server/recall/working_set_test.exs": "test data",
    "server/test/server/workline_review_test.exs": "test data",
    "server/test/server/workline_test.exs": "test data",
    "docs/plans/2026-09-25-git-toolbox-and-lazygit-pane-design.md": "a design plan naming the repo",
}


@unittest.skipUnless((WORK / "template").exists(), "no Tlön template")
class MenardHidden(unittest.TestCase):
    def setUp(self):
        patch = unittest.mock.patch.multiple(run, WORK=WORK, TEMPLATE=WORK / "template", PLUGINS=WORK / "plugins")
        patch.start()
        self.addCleanup(patch.stop)

    def workspace(self, arm):
        ws = run.WORK / "bench" / f"hidden-{arm}"
        run.prepare(CASE, ws, arm)
        self.addCleanup(shutil.rmtree, ws, True)
        return ws

    def mentions(self, ws):
        out = subprocess.run(
            ["grep", "-rIil", "menard", ".", "--exclude-dir=deps", "--exclude-dir=_build",
             "--exclude-dir=node_modules", "--exclude-dir=.git"],
            cwd=ws, capture_output=True, text=True).stdout
        return {p.removeprefix("./") for p in out.split()}

    def test_arm_a_has_no_door_and_no_word_of_menard(self):
        ws = self.workspace("A")
        self.assertEqual(sorted(self.mentions(ws) - ALLOWED.keys()), [])
        self.assertFalse((ws / "tasks/menard.toml").exists())
        self.assertFalse((ws / "scripts/menard.sh").exists())
        self.assertFalse(list((ws / "server/deps/menard/lib").glob("mix")))
        log = subprocess.run(["git", "log", "--format=%s"], cwd=ws, capture_output=True, text=True).stdout
        self.assertNotIn("menard", log.lower())
        tasks = subprocess.run(["mise", "tasks"], cwd=ws, capture_output=True, text=True,
                               env=dict(os.environ, MISE_TRUSTED_CONFIG_PATHS=str(run.WORK))).stdout
        self.assertNotIn("menard", tasks.lower())

    def test_an_arm_with_menard_gets_its_door_back(self):
        if not (run.PLUGINS / "all" / "bin" / "menard").exists():
            self.skipTest("no pinned `all` plugin")
        ws = self.workspace("all")
        self.assertTrue((ws / "tasks/menard.toml").exists())
        self.assertIn(str(run.PLUGINS / "all" / "bin" / "menard"), (ws / "scripts/menard.sh").read_text())
        self.assertIn('"tasks/menard.toml"', (ws / "mise.toml").read_text())


if __name__ == "__main__":
    unittest.main()
