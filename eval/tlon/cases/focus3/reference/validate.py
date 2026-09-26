#!/usr/bin/env python3
"""focus3's step 1 plant and grader, validated both ways from the patches beside this file.

    MENARD_EVAL_WORK=/tmp/menard-eval-tlon python3 eval/tlon/cases/focus3/reference/validate.py [NAME ...]

Each patch is a diff from the planted tree (the eval-base of an arm-A workspace: setup.sh's plant
on the template). For each row: a fresh workspace (run.prepare), the patch applied, then either the
case's `ci` (Tlön's own precommit, both apps: the plant must slip past it) or the step's check run
on a snapshot as the runner runs it (run.suite_env, run.check), the verdict against what is
expected; the workspace and its databases go after. One line per row, `MISMATCH` where the plant is
caught by Tlön's own gate or a grader no longer tells the fix from a way around it, and exit 1 if
any. Needs the built template.
"""

import os
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CASE = HERE.parent
EVAL = CASE.parents[2]
sys.path.insert(0, str(EVAL))
import run  # noqa: E402

# (step or "ci", name, patch or None, passes?)
ROWS = [
    ("ci", "planted-ci", None, True),
    ("01", "planted", None, False),
    ("01", "fix", "01/fix.patch", True),
    # the title first in the row's text: `rr` then scores +12 and the switcher finds it, but the
    # filter still drops a short query's low-scoring match
    ("01", "title-first", "01/title-first.patch", False),
]


def validate(step, name, patch, passes):
    rid = f"focus3.A.validate.{name}"
    ws = run.WORK / "bench" / rid
    run.prepare(CASE, ws, "A")
    env = dict(os.environ)
    env.update(run.suite_env(CASE, rid, ws))
    run.cleanup(CASE, rid, ws, env)
    try:
        if patch:
            subprocess.run(["git", "apply", "--index", str(HERE / patch)], cwd=ws, check=True)
        if step == "ci":
            code, out = run.sh((CASE / "ci").read_text().strip(), ws, timeout=1800, env=env)
        else:
            snap = ws.parent / f"{ws.name}.check"
            shutil.rmtree(snap, ignore_errors=True)
            subprocess.run(["cp", "-a", "--reflink=auto", str(ws), str(snap)], check=True)
            code, out = run.check(CASE / "steps" / step, snap, env)
            shutil.rmtree(snap, ignore_errors=True)
    finally:
        run.cleanup(CASE, rid, ws, env)
        shutil.rmtree(ws, ignore_errors=True)
    ok = (code == 0) == passes
    last = [l for l in out.strip().splitlines() if l.strip().strip(".")][-3:]
    print(f"{'ok      ' if ok else 'MISMATCH'} {step} {name}: exit {code}, expected "
          f"{'pass' if passes else 'fail'}; {' | '.join(l.strip()[:120] for l in last)}", flush=True)
    return ok


def main():
    if not run.TEMPLATE.exists():
        sys.exit(f"no template at {run.TEMPLATE}: build it (eval/run.py --suite eval/tlon) first")
    want = set(sys.argv[1:])
    rows = [r for r in ROWS if not want or r[1] in want]
    results = [validate(*r) for r in rows]
    print(f"{sum(results)} of {len(results)} as expected")
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
