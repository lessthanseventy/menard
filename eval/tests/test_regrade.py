"""A grader fixed judges the runs already made again, from the trees they left: no run is made again."""

import json
import subprocess
import sys
import tempfile
import unittest
import unittest.mock
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import regrade  # noqa: E402
import run  # noqa: E402
import test_report  # noqa: E402


def diff_of(template, changes):
    """The diff a session that made `changes` ({path: content}) left over the template."""
    with tempfile.TemporaryDirectory() as tmp:
        ws = Path(tmp) / "ws"
        subprocess.run(["cp", "-a", str(template), str(ws)], check=True)
        for cmd in (["git", "init", "-q"], ["git", "add", "-A"],
                    ["git", "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base"]):
            subprocess.run(cmd, cwd=ws, check=True)
        for path, content in changes.items():
            (ws / path).write_text(content)
        subprocess.run(["git", "add", "-A", "--intent-to-add"], cwd=ws, check=True)
        return subprocess.run(["git", "diff", "HEAD"], cwd=ws, capture_output=True, text=True).stdout


class Regrade(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.eval, self.work = root / "eval", root / "work"
        self.suite = self.eval / "suite"
        self.case = self.suite / "cases" / "desk"
        (self.work / "template").mkdir(parents=True)
        (self.work / "template" / "answer.txt").write_text("none\n")
        (self.eval / "cases").mkdir(parents=True)
        (self.eval / "cases" / "common.sh").write_text("")
        for step, wants in (("01", "one"), ("02", "two")):
            (self.case / "steps" / step).mkdir(parents=True)
            (self.case / "steps" / step / "prompt.md").write_text(f"write {wants}")
            # the grader as it was: it wants the word in capitals, which no prompt asked
            (self.case / "steps" / step / "check.sh").write_text(f'grep -qx {wants.upper()} answer.txt || {{ echo "FAIL: no {wants}"; exit 1; }}\n')
        (self.case / "kind").write_text("long\n")
        self.out = self.eval / "results" / "r1"
        (self.out / "traces").mkdir(parents=True)
        self.patches = [unittest.mock.patch.object(run, "EVAL", self.eval), unittest.mock.patch.object(regrade, "EVAL", self.eval),
                        unittest.mock.patch.object(run, "WORK", self.work),
                        unittest.mock.patch.object(run, "TEMPLATE", self.work / "template"),
                        unittest.mock.patch.object(run, "PLUGINS", self.work / "plugins")]
        for p in self.patches:
            p.start()

    def tearDown(self):
        for p in self.patches:
            p.stop()
        self.tmp.cleanup()

    def row(self, arm, answers):
        """A session's row as the old grader judged it: every step failed."""
        rid = f"desk.{arm}.m.1"
        steps = []
        for step, answer in answers.items():
            (self.out / "traces" / f"{rid}.{step}.diff").write_text(diff_of(self.work / "template", {"answer.txt": answer}))
            steps.append(dict(test_report.step(step, passed=False), check="FAIL", formatted=True))
        old = dict(run.basis(self.suite), graders="old")
        return dict(test_report.row("desk", arm, 1, passed=False, steps=steps), id=rid, basis=old, steps_passed=0,
                    noise_files=[], formatted=True)

    def regraded(self, rows):
        (self.out / "runs.jsonl").write_text("".join(json.dumps(r) + "\n" for r in rows))
        with unittest.mock.patch.object(sys, "argv", ["regrade.py", "r1", "--suite", str(self.suite)]):
            regrade.main()
        return [json.loads(l) for l in (self.out / "runs.jsonl").read_text().splitlines()]

    def test_each_step_is_judged_on_the_tree_the_session_left_at_it(self):
        right = self.row("with", {"01": "one\n", "02": "two\n"})
        wrong = self.row("without", {"01": "one\n", "02": "three\n"})
        # the grader fixed: the word as the prompt asked it
        for step, wants in (("01", "one"), ("02", "two")):
            (self.case / "steps" / step / "check.sh").write_text(f'grep -qx {wants} answer.txt || {{ echo "FAIL: no {wants}"; exit 1; }}\n')

        a, b = self.regraded([right, wrong])
        self.assertEqual((a["pass"], a["steps_passed"], [s["pass"] for s in a["steps"]]), (True, 2, [True, True]))
        self.assertEqual((b["pass"], b["steps_passed"], [s["pass"] for s in b["steps"]]), (False, 1, [True, False]))
        self.assertIn("FAIL: no two", b["check"])

        # what the run did is what it did: its tokens and turns are untouched
        self.assertEqual(a["tokens"], right["tokens"])
        self.assertEqual([s["turns"] for s in a["steps"]], [s["turns"] for s in right["steps"]])
        # judged by the graders there are now, and what it was judged before kept
        self.assertEqual(a["basis"], run.basis(self.suite))
        self.assertEqual(a["graded_before"]["basis"]["graders"], "old")
        self.assertEqual((a["graded_before"]["pass"], a["graded_before"]["steps"]), (False, [{"step": "01", "pass": False}, {"step": "02", "pass": False}]))
        kept = (self.out / "runs.jsonl.before-regrade").read_text().splitlines()
        self.assertEqual([json.loads(l)["pass"] for l in kept], [False, False])

    def test_a_row_whose_trees_were_not_kept_or_are_of_another_template_is_left_as_it_was(self):
        no_diffs = self.row("with", {"01": "one\n", "02": "two\n"})
        (self.out / "traces" / "desk.with.m.1.02.diff").unlink()
        other = dict(self.row("without", {"01": "one\n", "02": "two\n"}))
        other["basis"] = dict(other["basis"], agent="another")
        self.assertEqual(self.regraded([no_diffs, other]), [no_diffs, other])


if __name__ == "__main__":
    unittest.main()
