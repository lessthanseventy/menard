"""What a run leaves running (nothing): the agent's process group, and whatever else works in its workspace.

    python3 -m unittest discover -s eval/tests
"""

import os
import subprocess
import sys
import tempfile
import time
import unittest
import unittest.mock
from pathlib import Path

EVAL = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(EVAL))
import run  # noqa: E402


def alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    # killed but not yet reaped is dead for our purposes
    try:
        return open(f"/proc/{pid}/stat").read().split()[2] != "Z"
    except OSError:
        return False


def pid_of(marker):
    """The pid of the one process whose command line carries `marker`, or None."""
    out = subprocess.run(["pgrep", "-f", marker], capture_output=True, text=True).stdout.split()
    return int(out[0]) if out else None


def sleeper(marker):
    """A shell line that leaves a `sleep` named `marker` (its argv[0]) running."""
    return f"exec -a {marker} sleep 300"


class TestProcesses(unittest.TestCase):
    def test_what_the_agent_backgrounded_dies_with_it(self):
        marker = f"menard-eval-test-{os.getpid()}-group"
        with tempfile.TemporaryDirectory() as d, open(os.devnull, "w") as out:
            ws = Path(d) / "ws"
            ws.mkdir()
            timed_out = run.run_agent(["bash", "-c", f"({sleeper(marker)}) & sleep 0.1; pgrep -f {marker} >/dev/null || exit 3"],
                                      ws, out, dict(os.environ))
            self.assertFalse(timed_out)
            time.sleep(0.2)
            self.assertIsNone(pid_of(marker))

    def test_a_process_working_in_the_workspace_outside_the_group_dies_too(self):
        marker = f"menard-eval-test-{os.getpid()}-setsid"
        with tempfile.TemporaryDirectory() as d, open(os.devnull, "w") as out:
            ws = Path(d) / "ws"
            ws.mkdir()
            run.run_agent(["bash", "-c", f"setsid bash -c '{sleeper(marker)}' & sleep 0.1"], ws, out, dict(os.environ))
            time.sleep(0.2)
            self.assertIsNone(pid_of(marker))

    def test_kill_stragglers_takes_only_the_workspaces_processes(self):
        marker = f"menard-eval-test-{os.getpid()}-straggler"
        with tempfile.TemporaryDirectory() as d:
            ws, other = Path(d) / "ws", Path(d) / "other"
            ws.mkdir()
            other.mkdir()
            inside = subprocess.Popen(["bash", "-c", sleeper(marker + "-in")], cwd=ws)
            outside = subprocess.Popen(["bash", "-c", sleeper(marker + "-out")], cwd=other)
            try:
                time.sleep(0.1)
                self.assertTrue(alive(inside.pid) and alive(outside.pid))
                self.assertEqual(run.kill_stragglers(ws), 1)
                time.sleep(0.2)
                self.assertFalse(alive(inside.pid))
                self.assertTrue(alive(outside.pid))
            finally:
                for p in (inside, outside):
                    p.kill()
                    p.wait()



if __name__ == "__main__":
    unittest.main()
