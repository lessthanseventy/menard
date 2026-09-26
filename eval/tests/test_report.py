"""The report's arithmetic on rows built here: spread, k of n, pairing, unbalanced cells, the per-step
table.

    python3 -m unittest discover -s eval/tests
"""

import sys
import unittest
from pathlib import Path

EVAL = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(EVAL))
import report  # noqa: E402


def row(case, arm, n, new=1000, out=100, turns=10, wall=60, passed=True, steps=None, model="m"):
    return {"id": f"{case}.{arm}.{model}.{n}", "case": case, "arm": arm, "model": model, "n": n, "kind": "long",
            "pass": passed, "clean": passed, "timed_out": False, "check": "", "turns": turns, "wall_s": wall + 200,
            "agent_wall_s": wall, "tokens": {"input": new, "cache_write": 0, "cache_read": 5000, "output": out},
            "tool_errors": 0, "red_runs": 1, "rereads": 0, "reruns": 0, "credo": 0, "ran_gate": 1, "gaps": [],
            "failures": [], "tools": {"Bash": 3}, "ci": {"green_first": True, "tokens": {"input": 0, "cache_write": 0, "output": 0}},
            "steps": steps or []}


def step(name, passed=True, turns=5, new=500):
    return {"step": name, "pass": passed, "turns": turns, "wall_s": 100, "agent_wall_s": 40,
            "tokens": {"input": new, "cache_write": 0, "cache_read": 1000, "output": 50}, "tool_errors": 0, "red_runs": 0}


def rows(n_a=3, n_all=3):
    """Two cases; all costs 100 more new tokens than A on the same (case, n) and fails one cell."""
    out = []
    for case in ("c1", "c2"):
        for n in range(1, 4):
            if n <= n_a:
                out.append(row(case, "A", n, new=1000 + 10 * n, steps=[step("01"), step("02", passed=n != 2)]))
            if n <= n_all:
                out.append(row(case, "all", n, new=1100 + 10 * n, passed=not (case == "c2" and n == 3),
                               steps=[step("01"), step("02", turns=8)]))
    return out


class TestArithmetic(unittest.TestCase):
    def test_spread_is_the_median_with_the_range(self):
        self.assertEqual(report.spread([1, 2, 10]), "2.0 (1.0–10.0)")
        self.assertEqual(report.spread([7]), "7.0")
        self.assertEqual(report.spread([None, 3, None]), "3.0")
        self.assertEqual(report.spread([]), "–")
        self.assertEqual(report.spread([1500, 2500], "{:,.0f}"), "2,000 (1,500–2,500)")

    def test_k_of_n(self):
        self.assertEqual(report.kofn([{"pass": True}, {"pass": False}, {"pass": True}], "pass"), "2/3")
        self.assertEqual(report.kofn([{"ran_gate": 2}, {}], "ran_gate"), "1/1")
        self.assertEqual(report.kofn([{}], "ran_gate"), "–")


class TestCells(unittest.TestCase):
    def test_an_arm_with_fewer_runs_in_a_cell_is_flagged(self):
        self.assertEqual(report.unbalanced(rows()), [])
        flagged = report.unbalanced(rows(n_all=2))
        self.assertEqual([k for k, _ in flagged], [("c1", "m"), ("c2", "m")])
        self.assertEqual(flagged[0][1], {"A": 3, "all": 2})

    def test_paired_deltas_against_A_on_the_same_case_model_and_run(self):
        p = report.paired(rows(), "A")
        self.assertEqual(sorted(p), ["all"])
        self.assertEqual(p["all"]["pairs"], 6)
        new = p["all"]["metrics"]["new"]
        self.assertEqual((new["lower"], new["higher"], new["median"], new["min"], new["max"]), (0, 6, 100, 100, 100))
        self.assertEqual(p["all"]["pass"], {"arm_only": 0, "base_only": 1, "both": 5, "neither": 0})
        # an unmatched run pairs with nothing
        self.assertEqual(report.paired(rows(n_all=2), "A")["all"]["pairs"], 4)

    def test_the_step_table_has_a_row_per_case_step_and_arm(self):
        md = report.step_table(rows())
        lines = [l for l in md.splitlines() if l.startswith(("| c1", "| c2"))]
        self.assertEqual(len(lines), 8)
        self.assertIn("| c1 · m | 02 | A | 3 | 2/3 |", md)
        self.assertIn("| c1 · m | 02 | all | 3 | 3/3 | 8", md)


class TestRender(unittest.TestCase):
    def test_the_report_carries_the_warning_the_spread_and_the_sections(self):
        md = report.render(rows(n_all=2), ["r"])
        self.assertIn("WARNING: unbalanced cells", md)
        for section in ("## Paired deltas", "## By step", "## By arm"):
            self.assertIn(section, md)
        self.assertNotIn("WARNING", report.render(rows(), ["r"]))
        # pass as k of n, tokens as median with the range
        self.assertIn("| all | 6 | 5/6 |", report.render(rows(), ["r"]))
        self.assertIn("1,120 (1,110–1,130)", report.render(rows(), ["r"]))


if __name__ == "__main__":
    unittest.main()
