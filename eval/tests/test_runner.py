"""The runner's own housekeeping: what a run leaves behind (nothing), and the order runs go in.

    python3 -m unittest discover -s eval/tests
"""

import os
import sys
import tempfile
import unittest
import unittest.mock
from pathlib import Path

EVAL = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(EVAL))
import run  # noqa: E402


class TestWorkspace(unittest.TestCase):
    def test_removing_a_workspace_takes_its_check_snapshot_and_its_session_files(self):
        with tempfile.TemporaryDirectory() as d:
            home = Path(d) / "home"
            ws = Path(d) / "runs" / "r" / "c.A.m.1"
            snap = Path(d) / "runs" / "r" / "c.A.m.1.check"
            sessions = home / ".claude" / "projects" / run.session_key(ws)
            for p in (ws, snap, sessions):
                p.mkdir(parents=True)
            with unittest.mock.patch.dict(os.environ, {"HOME": str(home)}):
                run.remove_workspace(ws)
            self.assertFalse(ws.exists())
            self.assertFalse(snap.exists())
            self.assertFalse(sessions.exists())
            self.assertTrue((home / ".claude" / "projects").exists())


class TestSchedule(unittest.TestCase):
    def test_arms_are_shuffled_within_each_case_and_run_and_the_seed_reproduces_it(self):
        cases, arms, models = ["c1", "c2", "c3", "c4"], ["A", "all"], ["m"]
        s1 = run.schedule(cases, arms, models, 3, seed=7)
        s2 = run.schedule(cases, arms, models, 3, seed=7)
        self.assertEqual(s1, s2)
        self.assertEqual(len(s1), 24)
        # every (case, model, n) has both arms next to each other, in one order or the other
        pairs = [s1[i:i + 2] for i in range(0, 24, 2)]
        for pair in pairs:
            self.assertEqual(len({(c, m, n) for c, _, m, n in pair}), 1)
            self.assertEqual(sorted(a for _, a, _, _ in pair), ["A", "all"])
        firsts = [pair[0][1] for pair in pairs]
        self.assertIn("A", firsts)
        self.assertIn("all", firsts)
        self.assertNotEqual(s1, run.schedule(cases, arms, models, 3, seed=8))


if __name__ == "__main__":
    unittest.main()
