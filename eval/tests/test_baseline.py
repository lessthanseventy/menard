"""`without` is a baseline: measured once on a basis, and lent to the rounds of that basis after."""

import json
import sys
import tempfile
import unittest
import unittest.mock
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import report  # noqa: E402
import run  # noqa: E402
import test_report  # noqa: E402

BASIS = {"suite": "abc", "claude": "2.1.283 (Claude Code)"}


def row(arm, n, basis=BASIS, model="m"):
    return dict(test_report.row("desk", arm, n, model=model), basis=basis)


class Results:
    def __init__(self, rounds):
        self.tmp = tempfile.TemporaryDirectory()
        self.eval = Path(self.tmp.name)
        for name, rows in rounds.items():
            (self.eval / "results" / name).mkdir(parents=True)
            (self.eval / "results" / name / "runs.jsonl").write_text("".join(json.dumps(r) + "\n" for r in rows))

    def __enter__(self):
        self.patches = [unittest.mock.patch.object(m, "EVAL", self.eval) for m in (run, report)]
        for p in self.patches:
            p.start()
        return self

    def __exit__(self, *_):
        for p in self.patches:
            p.stop()
        self.tmp.cleanup()


class Basis(unittest.TestCase):
    def test_a_changed_prompt_or_grader_is_another_basis_and_a_reference_answer_is_not(self):
        with tempfile.TemporaryDirectory() as tmp, unittest.mock.patch.object(run, "EVAL", Path(tmp)):
            suite = Path(tmp) / "suite"
            (suite / "cases" / "c" / "reference").mkdir(parents=True)
            (Path(tmp) / "cases").mkdir()
            (Path(tmp) / "cases" / "common.sh").write_text("x")
            (suite / "cases" / "c" / "prompt.md").write_text("do it")
            first = run.basis(suite)
            (suite / "cases" / "c" / "reference" / "01.patch").write_text("an answer")
            self.assertEqual(run.basis(suite), first)
            (suite / "cases" / "c" / "prompt.md").write_text("do it well")
            self.assertNotEqual(run.basis(suite)["suite"], first["suite"])
            self.assertIn("Claude Code", first["claude"])


class Baseline(unittest.TestCase):
    def test_the_baseline_is_the_without_rows_of_the_same_basis_case_and_model(self):
        other = {"suite": "changed", "claude": BASIS["claude"]}
        rounds = {"r1": [row("without", 1), row("without", 2), row("with", 1)],
                  "r0": [row("without", 1, basis=other), row("without", 1, basis=None), row("without", 1, model="n")]}
        with Results(rounds):
            found = run.baseline("desk", "m", BASIS)
            self.assertEqual([(r["round"], r["n"]) for r in found], [("r1", 1), ("r1", 2)])
            self.assertEqual(run.baseline("desk", "m", {"suite": "abc", "claude": "2.2.0"}), [])

    def test_a_round_that_ran_no_without_is_lent_the_baseline_and_pairs_with_none_of_it(self):
        rounds = {"r1": [row("without", 1), row("without", 2)], "r2": [row("with", 1), row("with", 2)]}
        with Results(rounds):
            rows = report.load(["r2"])
            self.assertEqual(sorted((r["arm"], r["round"], bool(r.get("borrowed"))) for r in rows),
                             [("with", "r2", False), ("with", "r2", False), ("without", "r1", True), ("without", "r1", True)])
            self.assertEqual(report.paired(rows), {})
            self.assertIn("**Baseline**: the 2 `without` rows are from r1", report.render(rows, ["r2"]))

    def test_a_round_with_its_own_without_borrows_nothing(self):
        rounds = {"r1": [row("without", 1)], "r2": [row("without", 1), row("with", 1)]}
        with Results(rounds):
            self.assertEqual([r["round"] for r in report.load(["r2"])], ["r2", "r2"])


if __name__ == "__main__":
    unittest.main()
