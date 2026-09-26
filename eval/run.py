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
# --effort: claude's own flag, unset for the rounds before it (the default level)
EFFORT = None
TIMEOUT = 900


def sh(cmd, cwd, timeout=600, env=None):
    """(status, output). Past `timeout` the command's whole process group is killed and the status is
    124: a check whose mix deadlocked on its own build lock (bench3 styler.A) crashed the runner, and
    its orphaned mix held the lock after."""
    p = subprocess.Popen(cmd, cwd=cwd, shell=isinstance(cmd, str), stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT, text=True, env=env, stdin=subprocess.DEVNULL,
                         start_new_session=True)
    LIVE.add(p)
    try:
        out, _ = p.communicate(timeout=timeout)
        return p.returncode, out
    except subprocess.TimeoutExpired:
        kill_group(p)
        out, _ = p.communicate()
        return 124, (out or "") + f"\nFAIL: timed out after {timeout}s"
    finally:
        LIVE.discard(p)


# Every process group the runner started and has not reaped: agents and checks run in their own
# (so a timeout takes their mix too), which also puts them out of reach of a kill aimed at the
# runner. Stopping the runner mid-round left an agent running; its workspace deleted, it wrote its
# fix into the rebuilt template, and every run after started from it (bench5h, 21:44).
LIVE = set()
# the run under way, (case_dir, rid, ws, env), for stop() to clean up after
CURRENT = None


def stop(signum, _frame):
    for p in list(LIVE):
        kill_group(p)
    # the run it cut short: its databases, tmux servers and workspace, as a finished run leaves none
    # (focus3's first start, stopped mid-run, left all three)
    if CURRENT:
        case_dir, rid, ws, env = CURRENT
        cleanup(case_dir, rid, ws, env)
        shutil.rmtree(ws, ignore_errors=True)
    sys.exit(128 + signum)


def kill_group(p):
    try:
        os.killpg(p.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def build_template(suite, force=False):
    """The fixture, deps fetched and compiled in dev and test, so a run starts warm."""
    if TEMPLATE.exists() and not force:
        return
    if TEMPLATE.exists():
        subprocess.run(["chmod", "-R", "u+w", str(TEMPLATE)], check=True)
    shutil.rmtree(TEMPLATE, ignore_errors=True)
    # a real project builds its own (eval/tlon: a clone at HEAD with its deps, on its toolchain)
    if (suite / "build.sh").exists():
        TEMPLATE.parent.mkdir(parents=True, exist_ok=True)
        code, out = sh(["bash", str(suite / "build.sh")], TEMPLATE.parent, timeout=3600,
                       env=dict(os.environ, TEMPLATE=str(TEMPLATE)))
        if code != 0:
            sys.exit(f"template: build.sh failed:\n{out[-3000:]}")
    else:
        shutil.copytree(suite / "fixture", TEMPLATE)
        for cmd in ["mix deps.get", "mix compile", "MIX_ENV=test mix compile", "mix test"]:
            code, out = sh(cmd, TEMPLATE, timeout=1200)
            if code != 0:
                sys.exit(f"template: `{cmd}` failed:\n{out[-3000:]}")
    # nothing may write into the copy every run starts from, an agent that wandered here included
    subprocess.run(["chmod", "-R", "a-w", str(TEMPLATE)], check=True)


def build_plugins(force=False):
    """Pinned copies of the plugin, so editing this repo mid-eval changes no run. C has no hooks; L
    loads the MCP tools up front (`alwaysLoad`, undocumented) instead of behind ToolSearch."""
    # L (the tools always loaded) is gone: manos loads them up front, and menard has none
    for arm in ["B", "C", "H", "M", "hook", "cli", "grep", "map", "lazy-mcp", "stop", "map-mcp", "run-cli", "compile", "big-read", "all"]:
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
        # four ways to keep manos' reach without its ~5,600 tokens of schema on every turn (bench6):
        # `cli` teaches the CLI in a few lines, `grep` answers a grep with each hit's function, `map`
        # gives a map of the project at the start, `lazy-mcp` keeps the MCP tools but deferred behind
        # ToolSearch. `hook` is B under a name that says what it is
        # `stop` checks what the agent changed when it ends its turn (compile, credo on its lines, the
        # stale tests) and refuses the stop while that is red, and a `git commit` waits for the whole
        # gate; `map-mcp` is the map and manos together, which neither alone would show
        extra = {"cli": [("SessionStart", None, "session-cli.sh")], "grep": [("PostToolUse", "Bash", "grep-where.sh")],
                 "map": [("SessionStart", None, "session-map.sh")], "map-mcp": [("SessionStart", None, "session-map.sh")],
                 "stop": [("Stop", None, "stop-gate.sh"), ("PreToolUse", "Bash", "commit-gate.sh")], "run-cli": [("SessionStart", None, "session-run.sh")],
                 "big-read": [("PreToolUse", "Read", "big-read.sh")],
                 # everything the hook-side arms add, together
                 "all": [("SessionStart", None, "session-run.sh"), ("PreToolUse", "Read", "big-read.sh"),
                         ("Stop", None, "stop-gate.sh"), ("PreToolUse", "Bash", "commit-gate.sh")]}.get(arm, [])
        for event, matcher, script in extra:
            hooks_json = dest / "hooks" / "hooks.json"
            d = json.loads(hooks_json.read_text())
            hook = {"type": "command", "command": f'bash "${{CLAUDE_PLUGIN_ROOT}}/hooks/{script}"'}
            # the gates run a suite, past the default hook timeout, and a hook that times out lets the stop
            # or the commit through. Tlön measured (fresh workspace): run check 52 s server + 15 s console,
            # a first test --stale 56 s; 300 is ~4x the worst, room for a loaded machine
            if script in ("stop-gate.sh", "commit-gate.sh"):
                hook["timeout"] = 300
            entry = {"hooks": [hook]}
            if matcher:
                entry["matcher"] = matcher
            d["hooks"].setdefault(event, []).append(entry)
            hooks_json.write_text(json.dumps(d, indent=2) + "\n")
        # `compile`: the format hook also compiles and names warnings in the files written (a flag, so
        # the shipped hook is unchanged until the round says it earns it)
        if arm in ("compile", "all"):
            hooks_json = dest / "hooks" / "hooks.json"
            text = hooks_json.read_text().replace('bash \\"${CLAUDE_PLUGIN_ROOT}/hooks/format-report.sh\\"',
                                                  'MENARD_HOOK_COMPILE=1 bash \\"${CLAUDE_PLUGIN_ROOT}/hooks/format-report.sh\\"')
            hooks_json.write_text(text)
        if arm == "lazy-mcp":
            manifest = dest / "manos" / ".claude-plugin" / "plugin.json"
            d = json.loads(manifest.read_text())
            d["mcpServers"]["menard"].pop("alwaysLoad", None)
            manifest.write_text(json.dumps(d, indent=2) + "\n")
        if arm == "L":
            manifest = dest / ".claude-plugin" / "plugin.json"
            d = json.loads(manifest.read_text())
            d["mcpServers"]["menard"]["alwaysLoad"] = True
            manifest.write_text(json.dumps(d, indent=2) + "\n")


def warm_plugins():
    """Each pinned copy builds itself once here, not on its first hook call inside a measured run."""
    for dest in PLUGINS.iterdir():
        if (dest / "bin" / "menard").exists():
            sh([str(dest / "bin" / "menard"), "version"], dest, timeout=600)


def prepare(case_dir, ws, arm):
    shutil.rmtree(ws, ignore_errors=True)
    ws.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["cp", "-a", "--reflink=auto", str(TEMPLATE), str(ws)], check=True)
    subprocess.run(["chmod", "-R", "u+w", str(ws)], check=True)
    setup = case_dir / "setup.sh"
    if setup.exists():
        code, out = sh(["bash", str(setup)], ws)
        if code != 0:
            sys.exit(f"{case_dir.name}: setup.sh failed:\n{out}")
    # the project as this arm would find it (eval/tlon: its AGENTS.md sends tests through menard, which
    # arm A has not got), before the base commit so the diff never sees it
    arm_setup = case_dir.parent.parent / "arm_setup.sh"
    if arm_setup.exists():
        code, out = sh(["bash", str(arm_setup), arm, str(PLUGINS / arm)], ws)
        if code != 0:
            sys.exit(f"{arm}: arm_setup.sh failed:\n{out}")
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
           # what a hook told the agent is in no other event: without it a trace cannot say
           "--include-hook-events",
           "--setting-sources", "project", "--permission-mode", "bypassPermissions",
           "--max-turns", str(MAX_TURNS)]
    # a session of steps resumes the one before, so its session has to be kept
    cmd += ["--resume", resume] if resume else []
    cmd += [] if persist else ["--no-session-persistence"]
    cmd += ["--effort", EFFORT] if EFFORT else []
    if arm != "A":
        cmd += ["--plugin-dir", str(PLUGINS / arm)]
    # M: menard (the formatting hook) and manos (the tools) beside it, as `install-claude.sh --tools`
    if arm in ("M", "lazy-mcp", "map-mcp"):
        cmd += ["--plugin-dir", str(PLUGINS / arm / "manos")]
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
MENARD_READS = ("menard:outline", "menard:find", "menard:deps", "menard:run")
# a shell command that WRITES an Elixir file: sed/perl in place, a redirect or tee onto one, or a
# script (python, ruby, elixir -e) that opens one to write. `sed -n`, grep, cat to read are not.
SHELL_EDIT = re.compile(
    r"\b(sed|perl)\s+(-\w*i|--in-place)[^|;&]*\.exs?\b"
    r"|(>|\btee\s+(-a\s+)?)\s*\S+\.exs?\b"
    r"|\b(python3?|ruby|node|elixir)\b[\s\S]*\.exs?\b[\s\S]*(write|File\.write|\"w\"|'w')"
)
# a shell command that writes ANY file (the edit between two test runs, the edit a Read comes after):
# sed/perl in place, a redirect or tee onto a path that is not /dev/null or a log under $TMPDIR, git
# moving the tree; matched with heredoc bodies cut out, since `->` and `>` are code there
SHELL_WRITE = re.compile(
    r"\b(?:sed|perl)\s+(?:-\w*i|--in-place)\b"
    r"|(?<![<>&\d=|-])>{1,2}\s*(?!/dev/|\$\{?TMPDIR|/tmp/)[\w./\"'$~-]+"
    r"|\btee\s+(?:-a\s+)?(?!/dev/)\S+"
    r"|\bgit\s+(?:mv|stash|checkout|apply|restore|revert|reset)\b"
)
# a script (the heredoc body included: that is the script) that opens a file to write
SCRIPT_WRITE = re.compile(r"\b(?:python3?|ruby|node|elixir)\b[\s\S]*?(?:open\([^)]*['\"][wa]|File\.write|\.write_text\(|writeFile)")
SHELL_READ = re.compile(r"\b(?:cat|head|tail|bat|less|sed\s+-n)\b")
HEREDOC = re.compile(r"<<-?\s*(['\"]?)(\w+)\1[^\n]*\n[\s\S]*?\n\s*\2(?=\n|$)")
FILE = re.compile(r"[\w./~-]+\.(?:exs?|heex|eex|md|toml|sh|json|ya?ml|txt)\b")
# the tests, through any door: mix (a -C app too), a wrapper in front (Tlön's scripts/cap.sh saves the
# output to .logs/, and its agents grep the log instead of running again), a mise task, menard's run
# verb as `bin/menard run`, `mise run menard -- run` (Tlön's AGENTS.md's form) or `mix menard.run`
MENARD_RUN = r"\bmenard(?:\.sh)?\b(?:\s+--)?(?:\s+--frozen)?\s+run\s+"
TEST_CMD = re.compile(r"\bmix\s+(?:-C\s+\S+\s+)?(?:test|precommit)\b|\bmix\s+menard\.run\s+(?:test|check)\b"
                      r"|\bmise\s+run\s+[\w:-]*(?:test|check)\b|" + MENARD_RUN + r"(?:test|check)\b")
# the project's gate: precommit or credo, a mise check task, menard's run check
GATE_CMD = re.compile(r"\bmix\s+(?:-C\s+\S+\s+)?(?:precommit|credo)\b|\bmix\s+menard\.run\s+check\b"
                      r"|\bmise\s+run\s+[\w:-]*check\b|" + MENARD_RUN + r"check\b")
# a mix format by hand (the hook formats every file written, so it is a wasted turn); a --check is not
FORMAT_CMD = re.compile(r"(?:^|\n|&&|;|\|\||\()\s*(?:mise exec -- )?mix\s+(?:-C\s+\S+\s+)?format\b(?!\s+--check)")


def sans_heredocs(cmd):
    """The command with its heredoc bodies cut out: a commit message naming `mix test` is not a run."""
    return HEREDOC.sub("", cmd)


def shell_edit(cmd):
    """True when the command writes a file."""
    return bool(SHELL_EDIT.search(cmd) or SHELL_WRITE.search(sans_heredocs(cmd)) or SCRIPT_WRITE.search(cmd))


def classify(name, inp):
    """What one tool call is, for the counts: an edit (the Edit tools, menard's write verbs, a shell
    command that writes), a test run, a gate run, a hand format. Bash commands only for the last three:
    a Read of .credo.exs or a grep for `precommit` is neither."""
    short = re.sub(r"^mcp__plugin_[\w-]+?_menard__", "menard:", name)
    c = {"short": short, "edit": False, "shell_edit": False, "test": False, "gate": False, "format": False, "cmd": ""}
    if name == "Bash":
        cmd = inp.get("command", "")
        sans = sans_heredocs(cmd)
        c.update(cmd=cmd, shell_edit=shell_edit(cmd), test=bool(TEST_CMD.search(sans)),
                 gate=bool(GATE_CMD.search(sans)), format=bool(FORMAT_CMD.search(sans)))
        c["edit"] = c["shell_edit"]
    elif name in EDITORS or short.startswith("menard:") and short not in MENARD_READS:
        c["edit"] = True
    elif short == "menard:run" or name.endswith("__run"):
        c["test"] = inp.get("verb") in ("test", "check")
        c["gate"] = inp.get("verb") == "check"
    return c


# a test run's result that says red, whatever the exit code (piped through cap.sh or grep it is 0):
# ExUnit's count, menard's reply, cap.sh's summary and exit line, a shell's `exit=N`
RED = re.compile(r'(?<![\d.])[1-9]\d* failures?\b|"ok":\s*false|\bFailed:\s*[1-9]|\b[Ee]xit(?:=|\s+code[:=]?\s*|\s+)[1-9]')


def same_file(a, b):
    return a == b or a.endswith("/" + b) or b.endswith("/" + a)


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
    for line in Path(trace_path).read_text().splitlines():
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
                    results[c["tool_use_id"]] = {"error": bool(c.get("is_error")), "text": text[:600],
                                                 "red": bool(RED.search(text))}
        elif o.get("type") == "result":
            final = o

    by_name, failures, gaps = {}, [], []
    # a red test run is the agent's code failing, not the tool: apart from the calls the tool refused
    # (only the arm that runs the tests unpiped exits non-zero when red), and a retry is a repeat
    # after one of those
    edited, rereads, retries, tool_errors, red_runs, prev = set(), 0, 0, 0, 0, None
    for c in calls:
        name, inp = c["name"], c["input"]
        k = classify(name, inp)
        # the plugin's name is in the prefix: menard's once, manos' since the tools moved there
        short = k["short"]
        by_name[short] = by_name.get(short, 0) + 1
        res = results.get(c["id"], {})
        # the files a shell edit names count as edited; a Read, or a cat/sed -n through the shell, of
        # one edited before is a reread (arm A edits and reads through the shell)
        paths = [norm(p, ws) for p in (FILE.findall(k["cmd"]) if k["shell_edit"] else paths_in(inp))]
        reads = paths if name == "Read" else \
            [norm(p, ws) for p in FILE.findall(k["cmd"])] if name == "Bash" and not k["edit"] and SHELL_READ.search(k["cmd"]) else []
        if any(same_file(r, e) for r in reads for e in edited):
            rereads += 1
        if k["edit"]:
            edited.update(paths)
        red = k["test"] and (res.get("error") or res.get("red"))
        red_runs += bool(red)
        error = res.get("error") and not red
        if error:
            tool_errors += 1
            failures.append({"tool": short, "text": res["text"][:300]})
            if name in EDITORS and "menard" in res["text"]:
                gaps.append({"kind": "guard_block", "tool": short, "path": paths[:1], "text": res["text"][:300]})
        if prev and prev[0] == name and prev[1]:
            retries += 1
        prev = (name, bool(error))
        if name == "Bash" and SHELL_EDIT.search(k["cmd"]):
            gaps.append({"kind": "shell_edit_ex", "command": k["cmd"][:300]})
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
        "tool_errors": tool_errors,
        "red_runs": red_runs,
        "failures": failures[:20],
        "rereads": rereads,
        "retries": retries,
        "gaps": gaps,
    }


def suite_env(case_dir, rid, ws):
    """What a suite's agent_env.sh prints, KEY=VALUE per line: eval/tlon's isolation from the live
    service and its databases. Empty for a suite without one."""
    script = case_dir.parent.parent / "agent_env.sh"
    if not script.exists():
        return {}
    code, out = sh(["bash", str(script), rid, str(ws)], ws, timeout=120)
    if code != 0:
        sys.exit(f"{script}: {out}")
    return dict(line.split("=", 1) for line in out.splitlines() if "=" in line)


def run_agent(cmd, ws, out, env):
    """The agent, in a process group of its own. When it is done, or at TIMEOUT, the whole group goes,
    then anything else still working in the workspace: a server or a test watcher it backgrounded
    would hold the run's database (cleanup's dropdb failed, silently) and can write into the
    workspace after it. True when it timed out."""
    p = subprocess.Popen(cmd, cwd=ws, stdout=out, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                         env=env, start_new_session=True)
    LIVE.add(p)
    timed_out = False
    try:
        p.wait(timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        timed_out = True
    finally:
        kill_group(p)
        p.wait()
        LIVE.discard(p)
        left = kill_stragglers(ws)
        if left:
            print(f"  {left} process(es) left running in the workspace, killed", flush=True)
    return timed_out


def kill_stragglers(ws):
    """Kill every process whose cwd is in the workspace (a `setsid` watcher is outside the agent's
    group; one from a crashed run has its cwd '(deleted)'). How many."""
    killed = 0
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            cwd = os.readlink(f"/proc/{pid}/cwd").removesuffix(" (deleted)")
        except OSError:
            continue
        if cwd == str(ws) or cwd.startswith(str(ws) + "/"):
            try:
                os.kill(int(pid), signal.SIGKILL)
                killed += 1
            except OSError:
                pass
    return killed


def check(check_dir, ws, run_env=None):
    """check.sh in check_dir, run in ws after its hidden/ files are copied in, under the run's env."""
    hidden = check_dir / "hidden"
    if hidden.exists():
        shutil.copytree(hidden, ws, dirs_exist_ok=True)
    code, out = sh(["bash", str(check_dir / "check.sh")], ws, timeout=1800,
                   env=dict(run_env or os.environ, CASE_DIR=str(check_dir),
                            EVAL_COMMON=str(EVAL / "cases" / "common.sh"), MIX_ENV="test"))
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
        # the run's env: a real project's check needs its throwaway databases (eval/tlon), not the defaults
        code, out = check(step, snap, env)
        shutil.rmtree(snap, ignore_errors=True)
        steps.append({"step": step.name, "pass": code == 0, "check": out.strip()[-400:],
                      "formatted": "NOTE: unformatted" not in out, "wall_s": round(time.time() - t0, 1),
                      "timed_out": timed_out, **m})
        if timed_out or not sid:
            break
    ci = ci_loop(case_dir, arm, model, rid, ws, out_dir, env, sid, steps)
    # the session files a kept session left under ~/.claude/projects
    shutil.rmtree(Path.home() / ".claude" / "projects" / re.sub(r"[^A-Za-z0-9]", "-", str(ws)), ignore_errors=True)
    return steps, ci


def ci_loop(case_dir, arm, model, rid, ws, out_dir, env, sid, steps):
    """CI as the project runs it (the case's `ci` file), once the agent says it is done. Red, the
    failure goes back to the same session, twice at most: the tokens to a mergeable change, not to
    the agent's stop. An agent that left files unformatted "finished" cheaper than it was."""
    ci = {"green_first": None, "green": None, "rounds": 0, "turns": 0,
          "tokens": {"input": 0, "output": 0, "cache_read": 0, "cache_write": 0}}
    if not (case_dir / "ci").exists() or not sid or not steps or steps[-1]["timed_out"]:
        return ci
    for attempt in range(3):
        code, out = sh((case_dir / "ci").read_text().strip(), ws, timeout=900, env=env)
        ci["green_first"] = code == 0 if attempt == 0 else ci["green_first"]
        ci["green"] = code == 0
        if code == 0 or attempt == 2:
            break
        failed = "\n".join(out.strip().splitlines()[-60:])
        trace = out_dir / "traces" / f"{rid}.ci{attempt + 1}.jsonl"
        with open(trace, "w") as f:
            run_agent(claude_cmd(f"CI failed on your change:\n\n{failed}\n\nFix it so CI passes.", model, arm,
                                 resume=sid, persist=True), ws, f, env)
        m = trace_metrics(trace, ws)
        sid = m["session_id"] or sid
        ci["rounds"] += 1
        ci["turns"] += m["turns"] or 0
        for k in ci["tokens"]:
            ci["tokens"][k] += m["tokens"][k]
    return ci


def run_one(case_dir, arm, model, n, out_dir):
    rid = f"{case_dir.name}.{arm}.{model}.{n}"
    ws = WORK / "runs" / out_dir.name / rid
    prepare(case_dir, ws, arm)
    (out_dir / "traces").mkdir(parents=True, exist_ok=True)
    # no CLAUDE_CODE_DISABLE_CLAUDE_MDS: it kept the user's own ~/.claude/CLAUDE.md out, which
    # --setting-sources project already does (tried in a bench), and the project's CLAUDE.md with it:
    # focus1's fixture said CI runs precommit, and no agent was ever told
    env = dict(os.environ, ENABLE_CLAUDEAI_MCP_SERVERS="false")
    env.pop("CLAUDECODE", None)
    # A runner started from a Claude Code shell inherits its plugins' bin/ dirs, and an installed
    # menard there (0.3.0 once) answered every `menard` the agents ran through Bash. The arm's own
    # --plugin-dir is the only menard a run may see.
    env.update(suite_env(case_dir, rid, ws))
    env["PATH"] = os.pathsep.join(p for p in env["PATH"].split(os.pathsep)
                                  if "/.claude/plugins/" not in p and Path(p).resolve() != REPO / "bin")
    env["PATH"] = str(EVAL / "stubs") + os.pathsep + env["PATH"]
    # what an earlier run of this rid left (its databases, a BEAM holding them) goes before this one starts
    cleanup(case_dir, rid, ws, env)
    global CURRENT
    CURRENT = (case_dir, rid, ws, env)
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
    code, check_out = check(case_dir, ws, env)
    cleanup(case_dir, rid, ws, env)
    row = {
        "id": rid, "case": case_dir.name, "kind": (case_dir / "kind").read_text().strip() if (case_dir / "kind").exists() else "",
        "arm": arm, "model": model, "effort": EFFORT, "n": n, "wall_s": wall, "timed_out": timed_out,
        "pass": code == 0, "check": check_out.strip()[-800:],
        "formatted": "NOTE: unformatted" not in check_out,
        "clean": code == 0 and not diff["noise_files"] and "NOTE: unformatted" not in check_out, **diff, **trace_metrics(trace, ws),
        **lint(ws, env, out_dir, rid),
    }
    with open(out_dir / "runs.jsonl", "a") as f:
        f.write(json.dumps(row) + "\n")
    shutil.rmtree(ws, ignore_errors=True)
    return row


def run_long(case_dir, arm, model, n, rid, ws, out_dir, env):
    """One row for a whole session: its steps' sums, and each step under `steps`."""
    t0 = time.time()
    steps, ci = run_steps(case_dir, arm, model, rid, ws, out_dir, env)
    allowed = [g.strip() for g in (case_dir / "allowed").read_text().splitlines() if g.strip()] \
        if (case_dir / "allowed").exists() else []
    diff, patch = diff_metrics(ws, allowed)
    (out_dir / "traces" / f"{rid}.diff").write_text(patch)
    total = lambda k: sum(s[k] or 0 for s in steps)
    tokens = {k: sum(s["tokens"][k] for s in steps) for k in ("input", "output", "cache_read", "cache_write")}
    last_ok = bool(steps) and steps[-1]["pass"] and len(steps) == len(list((case_dir / "steps").glob("*/prompt.md")))
    row = {
        "id": rid, "case": case_dir.name, "kind": "long", "arm": arm, "model": model, "effort": EFFORT, "n": n,
        "wall_s": round(time.time() - t0, 1), "timed_out": any(s["timed_out"] for s in steps),
        "pass": last_ok, "steps_passed": sum(s["pass"] for s in steps), "steps_total": len(steps),
        "check": steps[-1]["check"] if steps else "no step ran", "formatted": bool(steps) and steps[-1]["formatted"],
        "clean": last_ok and not diff["noise_files"] and steps[-1]["formatted"], **diff,
        "turns": total("turns"), "cost_usd": total("cost_usd"), "duration_ms": total("duration_ms"),
        "is_error": any(s["is_error"] for s in steps), "stop": steps[-1]["stop"] if steps else None,
        "tokens": tokens, "peak_ctx": max((s["peak_ctx"] for s in steps), default=0),
        "ctx_curve": [c for s in steps for c in s["ctx_curve"]],
        "tool_calls": total("tool_calls"), "tool_errors": total("tool_errors"), "red_runs": total("red_runs"),
        "tools": {k: sum(s["tools"].get(k, 0) for s in steps) for s in steps for k in s["tools"]},
        "failures": [dict(f, step=s["step"]) for s in steps for f in s["failures"]][:40],
        "rereads": total("rereads"), "retries": total("retries"),
        "gaps": [dict(g, step=s["step"]) for s in steps for g in s["gaps"]],
        "steps": [{k: s[k] for k in ("step", "pass", "check", "formatted", "turns", "tokens", "peak_ctx",
                                      "tool_errors", "red_runs", "wall_s", "timed_out")} for s in steps],
        **lint(ws, env, out_dir, rid),
        "ci": ci,
    }
    # after CI and lint, which need the run's databases: a long session left them all behind
    cleanup(case_dir, rid, ws, env)
    with open(out_dir / "runs.jsonl", "a") as f:
        f.write(json.dumps(row) + "\n")
    shutil.rmtree(ws, ignore_errors=True)
    return row


def cleanup(case_dir, rid, ws, env):
    """The suite's cleanup.sh (eval/tlon: the run's throwaway databases and tmux servers), after a
    run and before it (what a crashed run left holds its database: every test run of the rerun
    failed). What it could not clean is said, not hidden."""
    script = case_dir.parent.parent / "cleanup.sh"
    if script.exists():
        kill_stragglers(ws)
        code, out = sh(["bash", str(script), rid, str(ws)], ws.parent if ws.exists() else WORK, timeout=120, env=env)
        if code != 0 or out.strip():
            print(f"  cleanup{' FAILED' if code else ''}: {out.strip()}", flush=True)


def added_lines(ws):
    """{file: set of line numbers} the run added or changed since eval-base; every line of a new file."""
    _, diff = sh("git diff -U0 eval-base", ws)
    added, file = {}, None
    for line in diff.splitlines():
        if line.startswith("+++ "):
            file = line[6:] if line.startswith("+++ b/") else None
        elif line.startswith("@@") and file:
            m = re.search(r"\+(\d+)(?:,(\d+))?", line)
            start, count = int(m.group(1)), int(m.group(2) or 1)
            added.setdefault(file, set()).update(range(start, start + count))
    _, untracked = sh("git ls-files --others --exclude-standard", ws)
    for f in untracked.split():
        added[f] = set(range(1, 100_000))
    return added


def traces_of(out_dir, rid):
    """A run's traces: `{rid}.jsonl`, or a long run's steps and CI rounds (`{rid}.01.jsonl` …,
    `{rid}.ci1.jsonl`), and never run 10's for run 1."""
    d = out_dir / "traces"
    return [t for t in [d / f"{rid}.jsonl"] if t.exists()] + sorted(d.glob(f"{rid}.*.jsonl"))


def trace_habits(traces):
    """How the agent worked, read off its traces: test and gate runs, and the runs with no edit between
    (the operator's own sessions ran 40% of them again, to grep a different slice of the same failure);
    hand `mix format`s (the hook formats every file written, so each is a wasted turn); whether it ran
    the gate itself; and what each hook inside `all` did, each counted so the combined arm reads piece
    by piece. A command that edits and then runs the tests is one run with an edit before it."""
    ran, runs, reruns, last, formats = 0, 0, 0, False, 0
    fired = {"big_read": 0, "compile_warned": 0, "stop_refused": 0, "commit_refused": 0, "credo_flagged": 0}
    for trace in traces:
        for line in trace.read_text().splitlines():
            if '"hook_response"' in line and line.startswith("{"):
                h = json.loads(line)
                said = (h.get("output") or "") + (h.get("stderr") or "")
                fired["big_read"] += "permissionDecision" in said and "offset and limit" in said
                fired["compile_warned"] += "the compiler, on files you changed" in said
                fired["stop_refused"] += (h.get("hook_name") or "").startswith("Stop") and '"block"' in said
                fired["commit_refused"] += "Not committed: the project's gate" in said
                fired["credo_flagged"] += "credo, on lines you changed" in said
                continue
            if '"tool_use"' not in line or not line.startswith("{"):
                continue
            for c in json.loads(line).get("message", {}).get("content", []):
                if c.get("type") != "tool_use":
                    continue
                k = classify(c["name"], c.get("input", {}))
                ran += k["gate"]
                formats += k["format"]
                if k["edit"]:
                    last = False
                if k["test"]:
                    runs += 1
                    reruns += last
                    last = True
    return {"ran_gate": ran, "test_runs": runs, "reruns": reruns, "hand_formats": formats, "fired": fired}


def lint(ws, env, out_dir, rid):
    """What a run left for CI beyond its check: credo's issues (a project with none at its base, so
    each is the agent's), with the habits its traces show."""
    habits = trace_habits(traces_of(out_dir, rid))
    # every app that lints with credo: the root, or each app of a repo of several (Tlön's server/, console/)
    apps = [d for d in [ws, *sorted(p.parent for p in ws.glob("*/mix.exs"))] if (d / "deps" / "credo").exists()]
    if not apps:
        return {"credo": None, **habits}
    issues = []
    for app in apps:
        _, out = sh("mix credo --format json", app, timeout=300, env=env)
        at = out.find('{\n  "issues"')
        prefix = "" if app == ws else f"{app.name}/"
        issues += [dict(i, filename=prefix + i["filename"]) for i in (json.loads(out[at:])["issues"] if at >= 0 else [])]
    # only what the run added: Tlön's base already has 2 in console, which were not the agent's
    added = added_lines(ws)
    issues = [i for i in issues if i["line_no"] in added.get(i["filename"], ())]
    return {"credo": len(issues), **habits,
            "credo_issues": [f"{i['filename']}:{i['line_no']} {i['message']}" for i in issues][:20]}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("round")
    ap.add_argument("--cases", default="")
    ap.add_argument("--arms", default="A,B,C")
    ap.add_argument("--models", default="claude-sonnet-5")
    ap.add_argument("--runs", type=int, default=1)
    ap.add_argument("--rebuild", action="store_true")
    ap.add_argument("--effort", default="", help="low|medium|high|xhigh|max, passed to claude")
    ap.add_argument("--suite", default=str(EVAL), help="a dir holding fixture/ and cases/")
    ap.add_argument("--stop-at", default="", help="HH:MM local; start no run after it")
    a = ap.parse_args()
    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(sig, stop)

    suite = Path(a.suite).resolve()
    # a real project's tickets run longer than the fixture's cases (eval/tlon/settings.json)
    global MAX_TURNS, TIMEOUT, EFFORT
    EFFORT = a.effort or None
    if (suite / "settings.json").exists():
        limits = json.loads((suite / "settings.json").read_text())
        MAX_TURNS, TIMEOUT = limits.get("max_turns", MAX_TURNS), limits.get("timeout", TIMEOUT)
    build_template(suite, a.rebuild)
    build_plugins(a.rebuild)
    warm_plugins()
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
                            f" cost={row['cost_usd']:.3f} wall={row['wall_s']}s tool_errors={row['tool_errors']} red_runs={row['red_runs']}")
                    print(line, f"tools={row['tools']}", flush=True)
                    # one file across rounds, one line per run: what a watcher tails
                    with open(EVAL / "results" / "live.log", "a") as f:
                        f.write(line + "\n")


if __name__ == "__main__":
    main()
