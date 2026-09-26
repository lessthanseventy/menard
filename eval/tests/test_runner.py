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


if __name__ == "__main__":
    unittest.main()
