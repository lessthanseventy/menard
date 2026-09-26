"""Arm A must not learn menard exists, on the ex_riverside bench: no word of it anywhere in a
prepared workspace, none in the workspace's own path, and no plugin door.

Needs the riverside template (RIVERSIDE_EVAL_WORK, default /tmp/riverside-eval); skipped without
it. The runner's WORK is patched for the test, so the Tlön template of another test module is
never read as this one's.
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

WORK = Path(os.environ.get("RIVERSIDE_EVAL_WORK", "/tmp/riverside-eval"))
CASE = EVAL / "riverside" / "cases" / "events"


@unittest.skipUnless((WORK / "template").exists(), "no riverside template")
class MenardHidden(unittest.TestCase):
    def setUp(self):
        for name, value in (("WORK", WORK), ("TEMPLATE", WORK / "template"), ("PLUGINS", WORK / "plugins")):
            patcher = unittest.mock.patch.object(run, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def workspace(self, arm):
        ws = WORK / "bench" / f"hidden-{arm}"
        run.prepare(CASE, ws, arm)
        self.addCleanup(shutil.rmtree, ws, True)
        return ws

    def mentions(self, ws):
        out = subprocess.run(
            ["grep", "-rIil", "menard", ".", "--exclude-dir=deps", "--exclude-dir=_build",
             "--exclude-dir=node_modules", "--exclude-dir=.git"],
            cwd=ws, capture_output=True, text=True).stdout
        return {p.removeprefix("./") for p in out.split()}

    def test_arm_a_has_no_word_of_menard(self):
        ws = self.workspace("A")
        self.assertEqual(sorted(self.mentions(ws)), [])
        self.assertNotIn("menard", str(ws).lower())
        settings = (ws / ".claude" / "settings.json").read_text()
        self.assertNotIn("plugin", settings.lower())
        log = subprocess.run(["git", "log", "--format=%s"], cwd=ws, capture_output=True, text=True).stdout
        self.assertNotIn("menard", log.lower())
        tasks = subprocess.run(["mise", "tasks"], cwd=ws, capture_output=True, text=True,
                               env=dict(os.environ, MISE_TRUSTED_CONFIG_PATHS=str(WORK))).stdout
        self.assertNotIn("menard", tasks.lower())

    def test_the_run_env_names_databases_of_its_own_and_a_dead_llm(self):
        ws = self.workspace("A")
        env = run.suite_env(CASE, "events.A.m.1", ws)
        self.assertEqual(env["MIX_TEST_PARTITION"], "_events_a_m_1")
        self.assertEqual(env["EX_RIVERSIDE_DEV_DB"], "ex_riverside_dev_events_a_m_1")
        self.assertTrue(env["AI_BASE_URL"].startswith("http://127.0.0.1:9"))
        self.assertEqual(env["AI_API_KEY"], "")
        self.assertTrue(env["PATH"].startswith(str(EVAL / "riverside" / "stubs")))


if __name__ == "__main__":
    unittest.main()
