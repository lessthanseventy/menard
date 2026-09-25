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
    p = subprocess.run(cmd, cwd=cwd, shell=isinstance(cmd, str), capture_output=True, text=True,
                       timeout=timeout, env=env, stdin=subprocess.DEVNULL)
    return p.returncode, p.stdout + p.stderr


def build_template(force=False):
    """The fixture, deps fetched and compiled in dev and test, so a run starts warm."""
    if TEMPLATE.exists() and not force:
        return
    shutil.rmtree(TEMPLATE, ignore_errors=True)
    shutil.copytree(EVAL / "fixture", TEMPLATE)
    for cmd in ["mix deps.get", "mix compile", "MIX_ENV=test mix compile", "mix test"]:
        code, out = sh(cmd, TEMPLATE, timeout=1200)
        if code != 0:
            sys.exit(f"template: `{cmd}` failed:\n{out[-3000:]}")


def build_plugins(force=False):
    """Pinned copies of the plugin, so editing this repo mid-eval changes no run. C has no hooks; L
    loads the MCP tools up front (`alwaysLoad`, undocumented) instead of behind ToolSearch."""
    for arm in ["B", "C", "L"]:
        dest = PLUGINS / arm
        if dest.exists() and not force:
            continue
        shutil.rmtree(dest, ignore_errors=True)
        ignore = shutil.ignore_patterns(".git", "eval", "tmp", "doc", "erl_crash.dump", ".worktrees", "pi")
        shutil.copytree(REPO, dest, symlinks=True, ignore=ignore)
        if arm == "C":
            (dest / "hooks" / "hooks.json").write_text('{"hooks": {}}\n')
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


def claude_cmd(prompt, model, arm):
    cmd = ["claude", "-p", prompt, "--model", model, "--output-format", "stream-json", "--verbose",
           "--setting-sources", "project", "--permission-mode", "bypassPermissions",
           "--no-session-persistence", "--max-turns", str(MAX_TURNS)]
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
    calls, results, final = [], {}, {}
    for line in open(trace_path):
        try:
            o = json.loads(line)
        except json.JSONDecodeError:
            continue
        if o.get("type") == "assistant" and not o.get("parent_tool_use_id"):
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
        "tool_calls": len(calls),
        "tools": by_name,
        "failed_calls": len(failures),
        "failures": failures[:20],
        "rereads": rereads,
        "retries": retries,
        "gaps": gaps,
    }


def run_one(case_dir, arm, model, n, out_dir):
    rid = f"{case_dir.name}.{arm}.{model}.{n}"
    ws = WORK / "runs" / out_dir.name / rid
    prepare(case_dir, ws)
    prompt = (case_dir / "prompt.md").read_text().strip()
    trace = out_dir / "traces" / f"{rid}.jsonl"
    trace.parent.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, CLAUDE_CODE_DISABLE_CLAUDE_MDS="1", ENABLE_CLAUDEAI_MCP_SERVERS="false")
    env.pop("CLAUDECODE", None)
    t0 = time.time()
    timed_out = False
    with open(trace, "w") as f:
        try:
            subprocess.run(claude_cmd(prompt, model, arm), cwd=ws, stdout=f, stderr=subprocess.STDOUT,
                           stdin=subprocess.DEVNULL, env=env, timeout=TIMEOUT)
        except subprocess.TimeoutExpired:
            timed_out = True
    wall = round(time.time() - t0, 1)

    allowed = [g.strip() for g in (case_dir / "allowed").read_text().splitlines() if g.strip()] \
        if (case_dir / "allowed").exists() else []
    diff, patch = diff_metrics(ws, allowed)
    (out_dir / "traces" / f"{rid}.diff").write_text(patch)
    hidden = case_dir / "hidden"
    if hidden.exists():
        shutil.copytree(hidden, ws, dirs_exist_ok=True)
    code, check_out = sh(["bash", str(case_dir / "check.sh")], ws, timeout=600,
                         env=dict(os.environ, CASE_DIR=str(case_dir), MIX_ENV="test"))
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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("round")
    ap.add_argument("--cases", default="")
    ap.add_argument("--arms", default="A,B,C")
    ap.add_argument("--models", default="claude-sonnet-5")
    ap.add_argument("--runs", type=int, default=1)
    ap.add_argument("--rebuild", action="store_true")
    ap.add_argument("--stop-at", default="", help="HH:MM local; start no run after it")
    a = ap.parse_args()

    build_template(a.rebuild)
    build_plugins(a.rebuild)
    for arm in a.arms.split(","):
        if arm.startswith(("S-", "SL-")):
            build_skill_arm(arm, a.rebuild)
    cases = sorted(p.parent for p in (EVAL / "cases").glob("*/prompt.md"))
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
