#!/usr/bin/env python3
"""The events case's graders, validated both ways from the patches beside this file.

    MENARD_EVAL_WORK=/tmp/riverside-eval python3 eval/riverside/cases/events/reference/validate.py [NAME ...]

Each patch is a whole diff from the planted tree (the eval-base of an arm-A workspace: setup.sh's
plant on the template), earlier steps' fixes included, so it applies on its own. For each row: a
fresh workspace (run.prepare), the patch applied, the step's check run on a snapshot as the runner
runs it (run.suite_env, run.check), the verdict against what is expected; the workspace and its
databases go after. One line per row, `MISMATCH` where a grader no longer tells a solution from a
way around it, and exit 1 if any. Needs the built template; ~40 s a row.

Nothing here reaches a run: run.prepare copies the template alone, the step loop copies only
steps/NN/hidden/.
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

# (step, name, patch or None, passes?)
ROWS = [
    ("01", "planted", None, False),
    ("01", "fix", "01/fix.patch", True),
    ("01", "loosened-permissions", "01/loosened-permissions.patch", False),
    ("01", "review-no-bounce", "01/review-no-bounce.patch", False),
    ("02", "no-feature", "01/fix.patch", False),
    ("02", "feature", "02/feature.patch", True),
    ("02", "feature-send404", "02/feature-send404.patch", True),
    ("02", "stub", "02/stub.patch", False),
    ("02", "lf-unescaped", "02/lf-unescaped.patch", False),
    ("03", "unsplit", "02/feature.patch", False),
    ("03", "split", "03/split.patch", True),
    ("03", "comment-purge", "03/comment-purge.patch", False),
    ("03", "one-dump-module", "03/one-dump-module.patch", False),
    ("03", "dropped-function", "03/dropped-function.patch", False),
]


def validate(step, name, patch, passes):
    rid = f"events.A.validate.{name}"
    ws = run.WORK / "bench" / rid
    run.prepare(CASE, ws, "A")
    env = dict(os.environ)
    env.update(run.suite_env(CASE, rid, ws))
    run.cleanup(CASE, rid, ws, env)
    try:
        if patch:
            subprocess.run(["git", "apply", "--index", str(HERE / patch)], cwd=ws, check=True)
        snap = ws.parent / f"{ws.name}.check"
        shutil.rmtree(snap, ignore_errors=True)
        subprocess.run(["cp", "-a", "--reflink=auto", str(ws), str(snap)], check=True)
        code, out = run.check(CASE / "steps" / step, snap, env)
        shutil.rmtree(snap, ignore_errors=True)
    finally:
        run.cleanup(CASE, rid, ws, env)
        shutil.rmtree(ws, ignore_errors=True)
    ok = (code == 0) == passes
    last = next((l for l in reversed(out.strip().splitlines()) if l.strip()), "")
    print(f"{'ok      ' if ok else 'MISMATCH'} step {step} {name}: exit {code}, expected "
          f"{'pass' if passes else 'fail'}; {last[:160]}", flush=True)
    return ok


def main():
    if not run.TEMPLATE.exists():
        sys.exit(f"no template at {run.TEMPLATE}: build it (eval/run.py --suite eval/riverside) first")
    want = set(sys.argv[1:])
    rows = [r for r in ROWS if not want or r[1] in want]
    results = [validate(*r) for r in rows]
    print(f"{sum(results)} of {len(results)} as expected")
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
