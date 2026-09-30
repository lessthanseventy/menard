#!/usr/bin/env python3
"""A round's verdicts, made again by the graders as they are now.

    MENARD_EVAL_WORK=/tmp/desk-eval eval/regrade.py ROUND --suite eval/helpdesk

A grader fixed changes nothing a session did: no token, no turn, no line it wrote. So the run is
not made again. Each step's tree, as the session left it (traces/RID.NN.diff, over the template),
is put back in a fresh workspace and the step's check run on it as the runner runs it; the row's
pass, steps and clean are what that says, its basis names the graders that judged it, and what it
was before is kept beside it under `graded_before`. The rows as they were are in
runs.jsonl.before-regrade, once.

A long case's rows only, and only steps whose diff was kept (the runner keeps them since
2026-09-29): a row with a step that has none is left as it was, and said so.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

EVAL = Path(__file__).resolve().parent
sys.path.insert(0, str(EVAL))
import run  # noqa: E402


def regrade(row, case_dir, out_dir):
    """The row judged again, or None when a step's tree was not kept."""
    diffs = {s["step"]: out_dir / "traces" / f"{row['id']}.{s['step']}.diff" for s in row["steps"]}
    if not all(d.exists() for d in diffs.values()):
        return None
    rid = f"{row['id']}.regrade"
    ws = run.WORK / "bench" / rid
    env = dict(os.environ)
    steps = []
    for s in row["steps"]:
        run.prepare(case_dir, ws, row["arm"])
        env.update(run.suite_env(case_dir, rid, ws))
        try:
            if diffs[s["step"]].stat().st_size:
                subprocess.run(["git", "apply", "--index", "--whitespace=nowarn", str(diffs[s["step"]])], cwd=ws, check=True)
            code, out = run.check(case_dir / "steps" / s["step"], ws, env)
        finally:
            run.cleanup(case_dir, rid, ws, env)
            shutil.rmtree(ws, ignore_errors=True)
        steps.append(dict(s, **{"pass": code == 0, "check": out.strip()[-400:], "formatted": "NOTE: unformatted" not in out}))
        print(f"  {row['id']} step {s['step']}: {'PASS' if code == 0 else 'FAIL'}"
              f"{'' if (code == 0) == bool(s['pass']) else '  (was ' + ('PASS' if s['pass'] else 'FAIL') + ')'}", flush=True)
    total = len(list((case_dir / "steps").glob("*/prompt.md")))
    last_ok = bool(steps) and steps[-1]["pass"] and len(steps) == total
    before = {k: row.get(k) for k in ("pass", "steps_passed", "clean", "formatted", "check", "basis")}
    before["steps"] = [{"step": s["step"], "pass": s["pass"]} for s in row["steps"]]
    return dict(row, **{
        "pass": last_ok, "steps_passed": sum(s["pass"] for s in steps), "steps": steps,
        "check": steps[-1]["check"], "formatted": steps[-1]["formatted"],
        "clean": last_ok and not row.get("noise_files") and steps[-1]["formatted"],
        "basis": run.BASES.get(row["case"], run.BASIS), "graded_before": row.get("graded_before") or before,
    })


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("round")
    ap.add_argument("--suite", required=True)
    a = ap.parse_args()
    suite = Path(a.suite).resolve()
    if not run.TEMPLATE.exists():
        sys.exit(f"no template at {run.TEMPLATE}: the round's MENARD_EVAL_WORK, with its template built")
    # each row is judged on its own case's basis (run.basis/2); the suite's is the default
    run.BASIS = run.basis(suite)
    run.BASES = {c.name: run.basis(suite, c.name) for c in (suite / "cases").iterdir() if c.is_dir()}
    out_dir = EVAL / "results" / a.round
    rows_file = out_dir / "runs.jsonl"
    rows = [json.loads(l) for l in rows_file.read_text().splitlines() if l.strip()]
    kept = out_dir / "runs.jsonl.before-regrade"
    if not kept.exists():
        shutil.copy(rows_file, kept)
    done = []
    for row in rows:
        case_dir = suite / "cases" / row["case"]
        met = (row.get("basis") or {}).get("agent")
        if row.get("kind") != "long" or not case_dir.exists():
            print(f"{row['id']}: left as it was (no long case of this suite)")
            done.append(row)
        elif met not in (None, run.BASES.get(row["case"], run.BASIS)["agent"]):
            print(f"{row['id']}: left as it was: what its session met ({met}) is not what the suite holds now "
                  f"({run.BASES.get(row['case'], run.BASIS)['agent']}), and its diffs are over another template")
            done.append(row)
        else:
            judged = regrade(row, case_dir, out_dir)
            if judged is None:
                print(f"{row['id']}: left as it was (a step's diff was not kept)")
            done.append(judged or row)
    rows_file.write_text("".join(json.dumps(r) + "\n" for r in done))
    print(f"{a.round}: {sum(1 for r in done if r.get('graded_before'))} of {len(done)} rows judged by graders {run.BASIS['graders']}")


if __name__ == "__main__":
    main()
