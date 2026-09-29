"""The helpdesk suite's graders: which acceptance tests a step's check takes, and as which app."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

EVAL = Path(__file__).resolve().parent.parent
CASE = EVAL / "helpdesk" / "cases" / "desk"


def hidden(step):
    """What `hidden STEP` (grade.sh) puts in a workspace: the test files, and the helper's move."""
    with tempfile.TemporaryDirectory() as ws:
        env = dict(os.environ, CASE_DIR=str(CASE / "steps" / step), EVAL_COMMON=str(EVAL / "cases" / "common.sh"))
        subprocess.run(["bash", "-c", f'source "{CASE}/grade.sh"; hidden {step}'], cwd=ws, env=env, check=True)
        tests = sorted(p.name for p in (Path(ws) / "test" / "hidden").iterdir())
        return tests, (Path(ws) / "test" / "support" / "hidden.ex").read_text()


class Hidden(unittest.TestCase):
    def test_a_step_takes_its_own_tests_and_every_step_before_it(self):
        self.assertEqual(hidden("01")[0], ["01_tickets_test.exs"])
        self.assertEqual([t[:2] for t in hidden("05")[0]], ["01", "02", "03", "04", "05"])
        self.assertEqual(len(hidden("09")[0]), 9)

    def test_a_ticket_moves_by_the_name_the_app_has_for_it_at_that_step(self):
        # step 08 renames transition/2 to change_status/3: the earlier steps' tests go on, through the helper
        self.assertIn(":transition, [ticket, to]", hidden("07")[1])
        self.assertIn(":change_status, [ticket, to, :system]", hidden("08")[1])

    def test_every_step_has_its_prompt_and_its_check_and_no_prompt_names_the_tool(self):
        steps = sorted(p.name for p in (CASE / "steps").iterdir())
        self.assertEqual(steps, [f"{n:02d}" for n in range(1, 10)])
        for step in steps:
            self.assertTrue((CASE / "steps" / step / "check.sh").exists(), step)
            self.assertNotIn("menard", (CASE / "steps" / step / "prompt.md").read_text().lower(), step)


if __name__ == "__main__":
    unittest.main()
