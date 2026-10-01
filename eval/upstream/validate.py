#!/usr/bin/env python3
"""A replayed history's graders, validated both ways, no model:

    MENARD_EVAL_WORK=/tmp/oban-eval eval/upstream/validate.py eval/oban [STEP ...]

One workspace from the suite's template (built if missing), moved through the case's steps as a
run's is (sync_upstream). At each step, on copies, the step's check as the runner runs it:
`before`, the tree as the agent finds it, must FAIL (the commit's own tests in it are red, or the
step grades nothing); `after`, upstream's commit applied (reference/NN.patch, its tests left out:
those are hidden/), must PASS. One line a row, MISMATCH where a grader does not tell them apart,
exit 1 if any.
"""

import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import run  # noqa: E402

suite = Path(sys.argv[1]).resolve()
only = set(sys.argv[2:])
(case_dir,) = sorted((suite / "cases").iterdir())
run.build_template(suite)
rid = f"{case_dir.name}.validate"
ws = run.WORK / "validate" / rid
run.prepare(case_dir, ws, "without")
env = dict(run.os.environ, **run.suite_env(case_dir, rid, ws))
bad = 0
for step in sorted(p for p in (case_dir / "steps").iterdir() if (p / "prompt.md").exists() or (p / "check.sh").exists()):
    run.sync_upstream(step, ws)
    if only and step.name not in only:
        continue
    for row, patch, expect in [("before", None, False), ("after", case_dir / "reference" / f"{step.name}.patch", True)]:
        snap = ws.parent / f"{ws.name}.{row}"
        shutil.rmtree(snap, ignore_errors=True)
        subprocess.run(["cp", "-a", "--reflink=auto", str(ws), str(snap)], check=True)
        if patch:
            code, out = run.sh(["git", "apply", str(patch)], snap)
            if code != 0:
                sys.exit(f"step {step.name}: the reference does not apply:\n{out}")
        run.cleanup(case_dir, rid, snap, env, fresh=True)
        code, out = run.check(step, snap, env)
        got = code == 0
        bad += got != expect
        why = " | ".join(line for line in out.strip().splitlines() if line.startswith(("FAIL", "NOTE")))
        print(f"{'ok      ' if got == expect else 'MISMATCH'} step {step.name} {row}: exit {code}, expected "
              f"{'pass' if expect else 'fail'}; {why or out.strip().splitlines()[-1] if out.strip() else ''}", flush=True)
        shutil.rmtree(snap, ignore_errors=True)
run.cleanup(case_dir, rid, ws, env)
shutil.rmtree(ws, ignore_errors=True)
sys.exit(1 if bad else 0)
