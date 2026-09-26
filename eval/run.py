#!/usr/bin/env python3
"""menard vs. no menard: run eval cases headless, one fresh fixture copy per run.

    eval/run.py ROUND --cases a,b --arms A,B,C --models claude-sonnet-5 --runs 2

Arms: A no plugin; B the plugin (a pinned copy of this repo); C the same copy with
hooks/hooks.json emptied. Each run appends one JSON line to eval/results/ROUND/runs.jsonl and
keeps its stream-json trace next to it. `claude plugin eval` is not used: its sandbox cannot start
Erlang (see STATUS.md), and it has no shell grader and no third arm.
"""

import argparse
import fnmatch
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

EVAL = Path(__file__).resolve().parent
REPO = EVAL.parent
WORK = Path(os.environ.get("MENARD_EVAL_WORK", os.path.join(os.environ.get("TMPDIR", "/tmp"), "menard-eval")))
TEMPLATE = WORK / "template"
PLUGINS = WORK / "plugins"
MAX_TURNS = 60
TIMEOUT = 900


def sh(cmd, cwd, timeout=600, env=None):
    """(status, output). Past `timeout` the command's whole process group is killed and the status is
    124: a check whose mix deadlocked on its own build lock (bench3 styler.A) crashed the runner, and
    its orphaned mix held the lock after."""
    p = subprocess.Popen(cmd, cwd=cwd, shell=isinstance(cmd, str), stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT, text=True, env=env, stdin=subprocess.DEVNULL,
                         start_new_session=True)
    try:
        out, _ = p.communicate(timeout=timeout)
        return p.returncode, out
    except subprocess.TimeoutExpired:
        kill_group(p)
        out, _ = p.communicate()
        return 124, (out or "") + f"\nFAIL: timed out after {timeout}s"


def kill_group(p):
    try:
        os.killpg(p.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def build_template(suite, force=False):
    """The fixture, deps fetched and compiled in dev and test, so a run starts warm."""
    if TEMPLATE.exists() and not force:
        return
    shutil.rmtree(TEMPLATE, ignore_errors=True)
    shutil.copytree(suite / "fixture", TEMPLATE)
    for cmd in ["mix deps.get", "mix compile", "MIX_ENV=test mix compile", "mix test"]:
        code, out = sh(cmd, TEMPLATE, timeout=1200)
        if code != 0:
            sys.exit(f"template: `{cmd}` failed:\n{out[-3000:]}")


def build_plugins(force=False):
    """Pinned copies of the plugin, so editing this repo mid-eval changes no run. C has no hooks; L
    loads the MCP tools up front (`alwaysLoad`, undocumented) instead of behind ToolSearch."""
    for arm in ["B", "C", "L", "H"]:
        dest = PLUGINS / arm
        if dest.exists() and not force:
            continue
        shutil.rmtree(dest, ignore_errors=True)
        ignore = shutil.ignore_patterns(".git", "eval", "tmp", "doc", "erl_crash.dump", ".worktrees", "pi")
        shutil.copytree(REPO, dest, symlinks=True, ignore=ignore)
        if arm == "C":
            (dest / "hooks" / "hooks.json").write_text('{"hooks": {}}\n')
        # H: no tools, no skill, no guard: only a hook that formats each Elixir file written and
        # names one that does not parse. Is menard's clean output the tools', or the formatting?
        if arm == "H":
            # every script the arm's hooks.json names, and nothing else to run
            for f in (EVAL / "arms" / "H").iterdir():
                shutil.copy(f, dest / "hooks" / f.name)
            shutil.rmtree(dest / "skills", ignore_errors=True)
            manifest = dest / ".claude-plugin" / "plugin.json"
            d = json.loads(manifest.read_text())
            d.pop("mcpServers", None)
            manifest.write_text(json.dumps(d, indent=2) + "\n")
        if arm == "L":
            manifest = dest / ".claude-plugin" / "plugin.json"
            d = json.loads(manifest.read_text())
            d["mcpServers"]["menard"]["alwaysLoad"] = True
            manifest.write_text(json.dumps(d, indent=2) + "\n")


def prepare(case_dir, ws):
    shutil.rmtree(ws, ignore_errors=True)
    ws.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["cp", "-a", "--reflink=auto", str(TEMPLATE), str(ws)], check=True)
    setup = case_dir / "setup.sh"
    if setup.exists():
        code, out = sh(["bash", str(setup)], ws)
        if code != 0:
            sys.exit(f"{case_dir.name}: setup.sh failed:\n{out}")
    # tagged: an agent may commit its work, and the diff and the checks are against this, not HEAD
    for cmd in ["git init -q", "git add -A", "git -c user.name=eval -c user.email=eval@x commit -qm base",
                "git tag eval-base"]:
        sh(cmd, ws)


def build_skill_arm(arm, force=False):
    """`S-<variant>`: arm B with its skill swapped for eval/skills/<variant>.md, or none (`S-none`).
    `SL-<variant>`: the same on arm L, the tools always loaded."""
    dest = PLUGINS / arm
    if dest.exists() and not force:
        return
    shutil.rmtree(dest, ignore_errors=True)
    base, variant = arm.split("-", 1)
    shutil.copytree(PLUGINS / ("L" if base == "SL" else "B"), dest, symlinks=True)
    if variant == "none":
        shutil.rmtree(dest / "skills")
    else:
        shutil.copy(EVAL / "skills" / f"{variant}.md", dest / "skills" / "menard" / "SKILL.md")


def claude_cmd(prompt, model, arm, resume=None, persist=False):
    cmd = ["claude", "-p", prompt, "--model", model, "--output-format", "stream-json", "--verbose",
           "--setting-sources", "project", "--permission-mode", "bypassPermissions",
           "--max-turns", str(MAX_TURNS)]
    # a session of steps resumes the one before, so its session has to be kept
    cmd += ["--resume", resume] if resume else []
    cmd += [] if persist else ["--no-session-persistence"]
    if arm != "A":
        cmd += ["--plugin-dir", str(PLUGINS / arm)]
    return cmd


def diff_metrics(ws, allowed):
    sh("git add -A --intent-to-add", ws)
    _, numstat = sh("git diff --numstat eval-base", ws)
    files, lines = [], 0
    for row in numstat.splitlines():
        parts = row.split("\t")
        if len(parts) == 3:
            files.append(parts[2])
            lines += sum(int(x) for x in parts[:2] if x.isdigit())
    noise = [f for f in files if not any(fnmatch.fnmatch(f, g) for g in allowed)]
    _, patch = sh("git diff eval-base", ws)
    return {"files": files, "lines_changed": lines, "noise_files": noise}, patch


EDITORS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}
# a shell command that WRITES an Elixir file: sed/perl in place, a redirect or tee onto one, or a
# script (python, ruby, elixir -e) that opens one to write. `sed -n`, grep, cat to read are not.
SHELL_EDIT = re.compile(
    r"\b(sed|perl)\s+(-\w*i|--in-place)[^|;&]*\.exs?\b"
    r"|(>|\btee\s+(-a\s+)?)\s*\S+\.exs?\b"
    r"|\b(python3?|ruby|node|elixir)\b[\s\S]*\.exs?\b[\s\S]*(write|File\.write|\"w\"|'w')"
)


def paths_in(inp):
    out = []
    for k in ("file_path", "file", "path", "files"):
        v = inp.get(k)
        if isinstance(v, str):
            out.append(v)
        elif isinstance(v, list):
            out += [x for x in v if isinstance(x, str)]
    return out


def norm(p, ws):
    p = str(p)
    return os.path.relpath(p, ws) if os.path.isabs(p) else os.path.normpath(p)


def trace_metrics(trace_path, ws):
    calls, results, final, ctx = [], {}, {}, {}
    for line in open(trace_path):
        try:
            o = json.loads(line)
        except json.JSONDecodeError:
            continue
        if o.get("type") == "assistant" and not o.get("parent_tool_use_id"):
            # the context each model call read, once per message (a message spans several lines)
            u = o["message"].get("usage", {})
            ctx[o["message"].get("id")] = (u.get("input_tokens", 0) + u.get("cache_read_input_tokens", 0)
                                           + u.get("cache_creation_input_tokens", 0))
            for c in o["message"].get("content", []):
                if c.get("type") == "tool_use":
                    calls.append({"id": c["id"], "name": c["name"], "input": c.get("input", {})})
        elif o.get("type") == "user":
            content = o.get("message", {}).get("content", [])
            for c in content if isinstance(content, list) else []:
                if isinstance(c, dict) and c.get("type") == "tool_result":
                    text = c.get("content")
                    if isinstance(text, list):
                        text = " ".join(x.get("text", "") for x in text if isinstance(x, dict))
                    text = str(text or "").replace(str(ws) + "/", "").replace(str(PLUGINS), "$PLUGINS")
                    results[c["tool_use_id"]] = {"error": bool(c.get("is_error")), "text": text[:600]}
        elif o.get("type") == "result":
            final = o

    by_name, failures, gaps = {}, [], []
    edited, rereads, retries, prev = set(), 0, 0, None
    for c in calls:
        name, inp = c["name"], c["input"]
        short = name.replace("mcp__plugin_menard_menard__", "menard:")
        by_name[short] = by_name.get(short, 0) + 1
        res = results.get(c["id"], {})
        paths = [norm(p, ws) for p in paths_in(inp)]
        if name == "Read" and any(p in edited for p in paths):
            rereads += 1
        if name in EDITORS or short.startswith("menard:") and short not in ("menard:outline", "menard:find", "menard:deps", "menard:run"):
            edited.update(paths)
        if res.get("error"):
            failures.append({"tool": short, "text": res["text"][:300]})
            if name in EDITORS and "menard" in res["text"]:
                gaps.append({"kind": "guard_block", "tool": short, "path": paths[:1], "text": res["text"][:300]})
        if prev and prev[0] == name and prev[1]:
            retries += 1
        prev = (name, res.get("error", False))
        if name == "Bash":
            cmd = inp.get("command", "")
            if SHELL_EDIT.search(cmd):
                gaps.append({"kind": "shell_edit_ex", "command": cmd[:300]})
        if short == "menard:write":
            gaps.append({"kind": "whole_file_write", "path": paths[:1]})

    usage = final.get("usage", {})
    return {
        "turns": final.get("num_turns"),
        "cost_usd": final.get("total_cost_usd"),
        "duration_ms": final.get("duration_ms"),
        "is_error": final.get("is_error"),
        "stop": final.get("subtype") or final.get("terminal_reason"),
        "tokens": {
            "input": usage.get("input_tokens", 0),
            "output": usage.get("output_tokens", 0),
            "cache_read": usage.get("cache_read_input_tokens", 0),
            "cache_write": usage.get("cache_creation_input_tokens", 0),
        },
        "peak_ctx": max(ctx.values(), default=0),
        "ctx_curve": list(ctx.values()),
        "session_id": final.get("session_id"),
        "tool_calls": len(calls),
        "tools": by_name,
        "failed_calls": len(failures),
        "failures": failures[:20],
        "rereads": rereads,
        "retries": retries,
        "gaps": gaps,
    }


def run_agent(cmd, ws, out, env):
    """The agent, in a process group of its own: at TIMEOUT all of it goes, the mix it started too.
    True when it timed out."""
    p = subprocess.Popen(cmd, cwd=ws, stdout=out, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                         env=env, start_new_session=True)
    try:
        p.wait(timeout=TIMEOUT)
        return False
    except subprocess.TimeoutExpired:
        kill_group(p)
        p.wait()
        return True


def check(check_dir, ws):
    """check.sh in check_dir, run in ws after its hidden/ files are copied in."""
    hidden = check_dir / "hidden"
    if hidden.exists():
        shutil.copytree(hidden, ws, dirs_exist_ok=True)
    code, out = sh(["bash", str(check_dir / "check.sh")], ws, timeout=600,
                   env=dict(os.environ, CASE_DIR=str(check_dir), EVAL_COMMON=str(EVAL / "cases" / "common.sh"),
                            MIX_ENV="test"))
    return code, out


def run_steps(case_dir, arm, model, rid, ws, out_dir, env):
    """A long case: steps/NN/prompt.md, each resuming the session the step before left, each with
    its own check.sh, run on a copy of the workspace so its hidden files never reach the agent."""
    steps, sid, spent = [], None, 0.0
    for step in sorted(p for p in (case_dir / "steps").iterdir() if (p / "prompt.md").exists()):
        trace = out_dir / "traces" / f"{rid}.{step.name}.jsonl"
        t0, timed_out = time.time(), False
        with open(trace, "w") as f:
            timed_out = run_agent(claude_cmd((step / "prompt.md").read_text().strip(), model, arm, resume=sid,
                                             persist=True), ws, f, env)
        m = trace_metrics(trace, ws)
        sid = m["session_id"] or sid
        # a resumed session's total_cost_usd is the whole session's so far; turns and tokens are this call's
        if m["cost_usd"] is not None:
            m["cost_usd"], spent = m["cost_usd"] - spent, m["cost_usd"]
        snap = ws.parent / f"{ws.name}.check"
        shutil.rmtree(snap, ignore_errors=True)
        subprocess.run(["cp", "-a", "--reflink=auto", str(ws), str(snap)], check=True)
        code, out = check(step, snap)
        shutil.rmtree(snap, ignore_errors=True)
        steps.append({"step": step.name, "pass": code == 0, "check": out.strip()[-400:],
                      "formatted": "NOTE: unformatted" not in out, "wall_s": round(time.time() - t0, 1),
                      "timed_out": timed_out, **m})
        if timed_out or not sid:
            break
    # the session files a kept session left under ~/.claude/projects
    shutil.rmtree(Path.home() / ".claude" / "projects" / re.sub(r"[^A-Za-z0-9]", "-", str(ws)), ignore_errors=True)
    return steps


def run_one(case_dir, arm, model, n, out_dir):
    rid = f"{case_dir.name}.{arm}.{model}.{n}"
    ws = WORK / "runs" / out_dir.name / rid
    prepare(case_dir, ws)
    (out_dir / "traces").mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, CLAUDE_CODE_DISABLE_CLAUDE_MDS="1", ENABLE_CLAUDEAI_MCP_SERVERS="false")
    env.pop("CLAUDECODE", None)
    # A runner started from a Claude Code shell inherits its plugins' bin/ dirs, and an installed
    # menard there (0.3.0 once) answered every `menard` the agents ran through Bash. The arm's own
    # --plugin-dir is the only menard a run may see.
    env["PATH"] = os.pathsep.join(p for p in env["PATH"].split(os.pathsep)
                                  if "/.claude/plugins/" not in p and Path(p).resolve() != REPO / "bin")
    if (case_dir / "steps").exists():
        return run_long(case_dir, arm, model, n, rid, ws, out_dir, env)
    prompt = (case_dir / "prompt.md").read_text().strip()
    trace = out_dir / "traces" / f"{rid}.jsonl"
    t0 = time.time()
    timed_out = False
    with open(trace, "w") as f:
        timed_out = run_agent(claude_cmd(prompt, model, arm), ws, f, env)
    wall = round(time.time() - t0, 1)

    allowed = [g.strip() for g in (case_dir / "allowed").read_text().splitlines() if g.strip()] \
        if (case_dir / "allowed").exists() else []
    diff, patch = diff_metrics(ws, allowed)
    (out_dir / "traces" / f"{rid}.diff").write_text(patch)
    code, check_out = check(case_dir, ws)
    row = {
        "id": rid, "case": case_dir.name, "kind": (case_dir / "kind").read_text().strip() if (case_dir / "kind").exists() else "",
        "arm": arm, "model": model, "n": n, "wall_s": wall, "timed_out": timed_out,
        "pass": code == 0, "check": check_out.strip()[-800:],
        "formatted": "NOTE: unformatted" not in check_out,
        "clean": code == 0 and not diff["noise_files"] and "NOTE: unformatted" not in check_out, **diff, **trace_metrics(trace, ws),
    }
    with open(out_dir / "runs.jsonl", "a") as f:
        f.write(json.dumps(row) + "\n")
    shutil.rmtree(ws, ignore_errors=True)
    return row


def run_long(case_dir, arm, model, n, rid, ws, out_dir, env):
    """One row for a whole session: its steps' sums, and each step under `steps`."""
    t0 = time.time()
    steps = run_steps(case_dir, arm, model, rid, ws, out_dir, env)
    allowed = [g.strip() for g in (case_dir / "allowed").read_text().splitlines() if g.strip()] \
        if (case_dir / "allowed").exists() else []
    diff, patch = diff_metrics(ws, allowed)
    (out_dir / "traces" / f"{rid}.diff").write_text(patch)
    total = lambda k: sum(s[k] or 0 for s in steps)
    tokens = {k: sum(s["tokens"][k] for s in steps) for k in ("input", "output", "cache_read", "cache_write")}
    last_ok = bool(steps) and steps[-1]["pass"] and len(steps) == len(list((case_dir / "steps").glob("*/prompt.md")))
    row = {
        "id": rid, "case": case_dir.name, "kind": "long", "arm": arm, "model": model, "n": n,
        "wall_s": round(time.time() - t0, 1), "timed_out": any(s["timed_out"] for s in steps),
        "pass": last_ok, "steps_passed": sum(s["pass"] for s in steps), "steps_total": len(steps),
        "check": steps[-1]["check"] if steps else "no step ran", "formatted": bool(steps) and steps[-1]["formatted"],
        "clean": last_ok and not diff["noise_files"] and steps[-1]["formatted"], **diff,
        "turns": total("turns"), "cost_usd": total("cost_usd"), "duration_ms": total("duration_ms"),
        "is_error": any(s["is_error"] for s in steps), "stop": steps[-1]["stop"] if steps else None,
        "tokens": tokens, "peak_ctx": max((s["peak_ctx"] for s in steps), default=0),
        "ctx_curve": [c for s in steps for c in s["ctx_curve"]],
        "tool_calls": total("tool_calls"), "failed_calls": total("failed_calls"),
        "tools": {k: sum(s["tools"].get(k, 0) for s in steps) for s in steps for k in s["tools"]},
        "failures": [dict(f, step=s["step"]) for s in steps for f in s["failures"]][:40],
        "rereads": total("rereads"), "retries": total("retries"),
        "gaps": [dict(g, step=s["step"]) for s in steps for g in s["gaps"]],
        "steps": [{k: s[k] for k in ("step", "pass", "check", "formatted", "turns", "cost_usd", "peak_ctx",
                                      "failed_calls", "wall_s", "timed_out")} for s in steps],
    }
    with open(out_dir / "runs.jsonl", "a") as f:
        f.write(json.dumps(row) + "\n")
    shutil.rmtree(ws, ignore_errors=True)
    return row


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("round")
    ap.add_argument("--cases", default="")
    ap.add_argument("--arms", default="A,B,C")
    ap.add_argument("--models", default="claude-sonnet-5")
    ap.add_argument("--runs", type=int, default=1)
    ap.add_argument("--rebuild", action="store_true")
    ap.add_argument("--suite", default=str(EVAL), help="a dir holding fixture/ and cases/")
    ap.add_argument("--stop-at", default="", help="HH:MM local; start no run after it")
    a = ap.parse_args()

    suite = Path(a.suite).resolve()
    build_template(suite, a.rebuild)
    build_plugins(a.rebuild)
    for arm in a.arms.split(","):
        if arm.startswith(("S-", "SL-")):
            build_skill_arm(arm, a.rebuild)
    cases = sorted(p.parent for p in [*(suite / "cases").glob("*/prompt.md"), *(suite / "cases").glob("*/steps")])
    if a.cases:
        want = a.cases.split(",")
        cases = [c for c in cases if any(fnmatch.fnmatch(c.name, w) for w in want)]
    out_dir = EVAL / "results" / a.round
    out_dir.mkdir(parents=True, exist_ok=True)
    done = set()
    if (out_dir / "runs.jsonl").exists():
        done = {json.loads(l)["id"] for l in open(out_dir / "runs.jsonl") if l.strip()}

    # interleave arms within each (case, n) so drift in the API over the window hits every arm alike
    for n in range(1, a.runs + 1):
        for model in a.models.split(","):
            for case in cases:
                for arm in a.arms.split(","):
                    rid = f"{case.name}.{arm}.{model}.{n}"
                    if rid in done:
                        continue
                    if a.stop_at and time.strftime("%H:%M") >= a.stop_at:
                        print(f"stop-at {a.stop_at} reached", flush=True)
                        return
                    row = run_one(case, arm, model, n, out_dir)
                    line = (f"{time.strftime('%H:%M')} {a.round} {rid}: {'PASS' if row['pass'] else 'FAIL'}"
                            f"{'' if row['clean'] or not row['pass'] else ' (noisy)'} turns={row['turns']}"
                            f" cost={row['cost_usd']:.3f} wall={row['wall_s']}s failed_calls={row['failed_calls']}")
                    print(line, f"tools={row['tools']}", flush=True)
                    # one file across rounds, one line per run: what a watcher tails
                    with open(EVAL / "results" / "live.log", "a") as f:
                        f.write(line + "\n")


if __name__ == "__main__":
    main()
