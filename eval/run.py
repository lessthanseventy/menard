#!/usr/bin/env python3
"""With menard and without: run eval cases headless, one fresh copy of the template per run.

    eval/run.py ROUND --suite eval/SUITE --models claude-fable-5-1 --runs 5

Two arms. `without`: Claude Code and nothing else. `with`: the menard plugin as a user installs it
(a pinned copy of this repo: its hooks, MCP tools and skill), and nothing the eval adds to it. The
arms run in pairs, their order within a pair shuffled by the round's seed. Each run appends one
JSON line to eval/results/ROUND/runs.jsonl and keeps its stream-json trace next to it. `claude
plugin eval` is not used: its sandbox cannot start Erlang (see STATUS.md), and it has no shell
grader.
"""

import argparse
import fnmatch
import json
import os
import random
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
# the round's arm-order seed (schedule/5), in every row so a round can be re-run in the same order
SEED = None
# what a row was measured on (basis/1): the suite's files and the Claude Code that ran it. A
# `without` row is a baseline for every later round of the same basis, and for no other
BASIS = None


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
        remove_workspace(ws)
        # a long run's checkpoint stays: the same command resumes the run from it
        if not resume_point(ws):
            rm(pre(ws))
            rm(ws.parent / f"{ws.name}.pre.new")
    sys.exit(128 + signum)


def session_key(ws):
    """The directory under ~/.claude/projects a session run in `ws` keeps its files in."""
    return re.sub(r"[^A-Za-z0-9]", "-", str(ws))


def remove_workspace(ws):
    """The workspace, the snapshot its step checks run on, and the session files a kept session left
    under ~/.claude/projects (448 of those had piled up)."""
    shutil.rmtree(ws, ignore_errors=True)
    shutil.rmtree(ws.parent / f"{ws.name}.check", ignore_errors=True)
    shutil.rmtree(Path.home() / ".claude" / "projects" / session_key(ws), ignore_errors=True)


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
    # the language server's build and index, as a project worked in before has them (warm_expert.exs)
    code, out = sh(["mix", "run", str(EVAL / "warm_expert.exs"), str(TEMPLATE)], REPO, timeout=900)
    if code != 0:
        sys.exit(f"template: warming expert failed:\n{out[-3000:]}")
    # its logs are no part of the warm state, and name menard (the PATH it was started with): the arm
    # without must find no word of it (helpdesk/arm_setup.sh)
    for log in (TEMPLATE / ".expert").glob("*.log"):
        log.unlink()
    # nothing may write into the copy every run starts from, an agent that wandered here included
    subprocess.run(["chmod", "-R", "a-w", str(TEMPLATE)], check=True)


# The arms with menard, and what each sets in the plugin's server environment: `with` is the plugin
# as a user installs it; the others are that plugin with a setting of its own turned on, to see
# what the setting costs and buys before it is anyone's default.
VARIANTS = {"with": {}}
ARMS = ("without", *VARIANTS)


def basis(suite):
    """What a round's rows were measured on, in two parts.

    `agent` is what a session meets: how the template is built, its prompts, the settings and the
    environment it runs under, with `claude`, the Claude Code that ran. A prompt reworded or a new
    Claude Code is another basis, and the rows before it are no baseline for the rows after.

    `graders` is what judges it after: the checks and their acceptance tests, which no session
    sees. A grader fixed changes no token and no turn of a run already made, only its verdict, and
    that is made again from the run's saved diffs (eval/regrade.py), not by running it again.

    The reference answers are in neither: no run sees them, and no verdict comes from them."""
    import hashlib
    met, judged = hashlib.sha256(), hashlib.sha256()
    files = [p for p in sorted(suite.rglob("*")) if p.is_file() and "__pycache__" not in p.parts
             and "reference" not in p.parts and "results" not in p.parts]
    for p in files:
        h = met if p.name in AGENT_MEETS else judged
        h.update(str(p.relative_to(suite)).encode() + b"\0" + p.read_bytes() + b"\0")
    common = EVAL / "cases" / "common.sh"
    if common.exists():
        judged.update(b"common.sh\0" + common.read_bytes() + b"\0")
    version = subprocess.run(["claude", "--version"], capture_output=True, text=True).stdout.strip()
    return {"agent": met.hexdigest()[:16], "graders": judged.hexdigest()[:16], "claude": version}


# the files of a suite a session meets, by name; every other is a grader's
AGENT_MEETS = {"build.sh", "arm_setup.sh", "agent_env.sh", "cleanup.sh", "settings.json", "prompt.md", "setup.sh", "ci", "kind"}


def same_start(a, b):
    """Two rows' bases are one a baseline holds across: what the session met, and the Claude Code."""
    return bool(a) and bool(b) and a.get("agent") is not None and (a.get("agent"), a.get("claude")) == (b.get("agent"), b.get("claude"))


def baseline(case, model, found):
    """The `without` rows of any round measured on this round's basis, for `case` and `model`."""
    rows = []
    for f in sorted((EVAL / "results").glob("*/runs.jsonl")):
        for line in f.read_text().splitlines():
            r = json.loads(line) if line.strip() else {}
            if r.get("arm") == "without" and same_start(r.get("basis"), found) and r.get("case") == case and r.get("model") == model:
                rows.append(dict(r, round=f.parent.name))
    return rows


def build_plugins(force=False):
    """Each arm's plugin: a pinned copy of this repo as it is now, so editing the repo mid-round
    changes no run. `with` is as shipped, nothing added and nothing taken out; a variant differs
    from it by its settings in the server's environment, and by nothing else."""
    for arm, settings in VARIANTS.items():
        build_plugin(PLUGINS / arm, settings, force)


def build_plugin(dest, settings, force):
    if dest.exists() and not force:
        return
    shutil.rmtree(dest, ignore_errors=True)
    # worktrees: .claude/worktrees holds whole checkouts of this repo, one per agent at work
    ignore = shutil.ignore_patterns(".git", "eval", "tmp", "doc", "erl_crash.dump", ".worktrees", "worktrees", "pi")
    shutil.copytree(REPO, dest, symlinks=True, ignore=ignore)
    # which menard: the commit, and whether the tree held changes not in it
    sha = subprocess.run(["git", "-C", str(REPO), "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
    dirty = subprocess.run(["git", "-C", str(REPO), "status", "--porcelain", "--", "lib", "bin", "hooks", "skills", "priv",
                            ".claude-plugin", "mix.exs", "mix.lock"], capture_output=True, text=True).stdout.strip()
    (dest / ".pinned").write_text(sha + ("+changes" if dirty else "") + "\n")
    if settings:
        manifest = dest / ".claude-plugin" / "plugin.json"
        d = json.loads(manifest.read_text())
        d["mcpServers"]["menard"]["env"].update(settings)
        manifest.write_text(json.dumps(d, indent=2) + "\n")


def pinned(arm):
    """The menard a row's arm ran: the commit its plugin was copied at, None for the arm without."""
    mark = PLUGINS / arm / ".pinned"
    return mark.read_text().strip() if arm in VARIANTS and mark.exists() else None


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
    # the arm without has not got), before the base commit so the diff never sees it
    arm_setup = case_dir.parent.parent / "arm_setup.sh"
    if arm_setup.exists():
        code, out = sh(["bash", str(arm_setup), arm, str(PLUGINS / arm)], ws)
        if code != 0:
            sys.exit(f"{arm}: arm_setup.sh failed:\n{out}")
    # tagged: an agent may commit its work, and the diff and the checks are against this, not HEAD
    for cmd in ["git init -q", "git add -A", "git -c user.name=eval -c user.email=eval@x commit -qm base",
                "git tag eval-base"]:
        sh(cmd, ws)


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
    if arm in VARIANTS:
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


def files_in(cmd):
    """The source files a shell command names; a scratch copy under $TMPDIR or /tmp is not one."""
    return [p for p in FILE.findall(cmd) if not p.startswith(("TMPDIR/", "/tmp/", "tmp/"))]


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
        short = k["short"]
        by_name[short] = by_name.get(short, 0) + 1
        res = results.get(c["id"], {})
        # the files a shell edit names count as edited; a Read, or a cat/sed -n through the shell, of
        # one edited before is a reread (arm A edits and reads through the shell)
        paths = [norm(p, ws) for p in (files_in(k["cmd"]) if k["shell_edit"] else paths_in(inp))]
        reads = paths if name == "Read" else \
            [norm(p, ws) for p in files_in(k["cmd"])] if name == "Bash" and not k["edit"] and SHELL_READ.search(k["cmd"]) else []
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


# --- The account's usage limit. A session can die mid-step on the API's 429 ("You've hit your … limit
# · … resets 9:20am (America/Denver)"): that is not the agent failing, and every run after it would
# die the same way. The step is kept aside, the limit waited out, the workspace, the session's
# transcript and its hook state put back as they were before the step, and the step run again.

class RoundStop(Exception):
    """The round cannot go on (a step the limit ended MAX_REDOS times, a probe failing on something
    else). What it finished is kept, and the same command resumes it."""


MAX_REDOS = 5
# past the stated reset (a clock apart, a window that opens late), and the back-off without one
RESET_MARGIN = 120
BACKOFF, BACKOFF_CAP, TRANSIENT_BACKOFF = 600, 3600, 60
PROBE_MODEL = "claude-haiku-4-5"
# the tests put their own clock, sleep and probe here
CLOCK, SLEEP = time.time, time.sleep
USAGE_TEXT = re.compile(r"hit your [\w -]*limit|usage limit|rate[ _-]?limit|\b429\b", re.I)
TRANSIENT_TEXT = re.compile(r"overloaded|\b529\b|server error|\b50[0234]\b", re.I)
RESET_AT = re.compile(r"resets\s+(?:at\s+)?(?:(?P<mon>[A-Z][a-z]{2})[a-z]*\s+(?P<day>\d{1,2}),?\s+(?:at\s+)?)?"
                      r"(?P<h>\d{1,2})(?::(?P<m>\d{2}))?\s*(?P<ap>[ap]m)?\s*\((?P<tz>[\w/+-]+)\)", re.I)
RESET_IN = re.compile(r"(?:resets?|try again|retry)\s+(?:in|after)\s+((?:\d+\s*[a-z]+[\s,]*(?:and\s+)?)+)", re.I)
UNITS = {"d": 86400, "h": 3600, "m": 60, "s": 1}


def json_lines(text):
    """(the JSON objects, the other non-blank lines: stderr) of an agent's output."""
    objs, other = [], []
    for line in text.splitlines():
        try:
            o = json.loads(line)
        except json.JSONDecodeError:
            o = None
        if isinstance(o, dict):
            objs.append(o)
        elif line.strip():
            other.append(line)
    return objs, other


def limit_death(text):
    """None when the call ended on its own (done, out of turns, the agent's own error, a timeout);
    else how the API ended it: {"kind": "usage" (429, a spend or session limit) or "transient" (529
    overloaded, a 5xx), "reason", "reset" (epoch seconds, or None), "session_id"}. Only the API's own
    words count: the last top-level assistant message when it is an API error, the result when it is
    an error, stderr when there is no result. A tool's output that says "rate limit" is not one."""
    objs, other = json_lines(text)
    result = next((o for o in reversed(objs) if o.get("type") == "result"), None)
    asst = next((o for o in reversed(objs) if o.get("type") == "assistant" and not o.get("parent_tool_use_id")), None)
    said, statuses, errors = [], [], []
    if asst and (asst.get("error") or asst.get("isApiErrorMessage") or asst.get("message", {}).get("model") == "<synthetic>"):
        said += [c.get("text", "") for c in asst.get("message", {}).get("content", []) if isinstance(c, dict)]
        statuses.append(asst.get("apiErrorStatus") or asst.get("api_error_status"))
        errors.append(asst.get("error"))
    if result is None or result.get("is_error"):
        said += [str(result.get("result") or "")] if result else []
        statuses.append((result or {}).get("api_error_status"))
        said += other
    rejected = [q.get("resetsAt") for o in objs for q in [o.get("rate_limit_info") or o.get("quotaLimits") or {}]
                if q.get("status") == "rejected"]
    words = " ".join(s for s in said if s).strip()
    if 429 in statuses or "rate_limit" in errors or USAGE_TEXT.search(words) or rejected and said:
        kind = "usage"
    elif any(s in (500, 502, 503, 504, 529) for s in statuses) or {"overloaded", "server_error"} & set(errors) \
            or TRANSIENT_TEXT.search(words):
        kind = "transient"
    else:
        return None
    reset = next((r for r in reversed(rejected) if r), None) or parse_reset(words, CLOCK())
    sid = next((o["session_id"] for o in reversed(objs) if o.get("session_id")), None)
    reason = words[:300] or f"API error {[e for e in errors if e]} status {[s for s in statuses if s]}"
    return {"kind": kind, "reason": reason, "reset": reset, "session_id": sid}


def parse_reset(text, now):
    """When the limit says it resets, epoch seconds: "resets 9:20am (America/Denver)" (the next such
    time in that zone), "resets Oct 3, 5pm (UTC)", "resets in 2h 30m", "try again in 5 minutes"."""
    from datetime import datetime, timedelta
    from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
    m = RESET_AT.search(text)
    if m:
        try:
            local = datetime.fromtimestamp(now, ZoneInfo(m["tz"]))
        except (ZoneInfoNotFoundError, ValueError):
            local = None
        if local:
            h = int(m["h"])
            if m["ap"]:
                h = h % 12 + (12 if m["ap"].lower() == "pm" else 0)
            at = local.replace(hour=h, minute=int(m["m"] or 0), second=0, microsecond=0)
            if m["mon"]:
                at = at.replace(month=time.strptime(m["mon"].title(), "%b").tm_mon, day=int(m["day"]))
                at = at if at > local else at.replace(year=at.year + 1)
            elif at <= local:
                at += timedelta(days=1)
            return at.timestamp()
    m = RESET_IN.search(text)
    if m:
        return now + sum(int(n) * UNITS.get(u[0].lower(), 0) for n, u in re.findall(r"(\d+)\s*([a-z]+)", m[1], re.I))
    return None


def stamp(ts):
    return time.strftime("%Y-%m-%d %H:%M:%S %Z", time.localtime(ts))


def probe():
    """One tiny call, to see whether the limit has lifted: ("ok", None), ("limited", the limit),
    or ("error", what it said). The cheapest model, one turn, no session kept, nothing loaded."""
    d = WORK / "probe"
    d.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    env.pop("CLAUDECODE", None)
    _, out = sh(["claude", "-p", "Reply with the word ok.", "--model", PROBE_MODEL, "--output-format", "stream-json",
                 "--verbose", "--setting-sources", "project", "--max-turns", "1", "--no-session-persistence"],
                d, timeout=300, env=env)
    hit = limit_death(out)
    if hit:
        return "limited", hit
    if any(o.get("type") == "result" and not o.get("is_error") for o in json_lines(out)[0]):
        return "ok", None
    return "error", out.strip()[-300:]


PROBE = probe


def wait_out(hit, out_dir, label):
    """Sleep until the limit resets (and RESET_MARGIN), or back off when it names no time, then probe
    until a call goes through. Every wait is logged and kept in results/ROUND/waits.jsonl; the waits."""
    waits, reset, failed = [], hit["reset"], 0
    backoff = TRANSIENT_BACKOFF if hit["kind"] == "transient" else BACKOFF
    while True:
        now = CLOCK()
        if reset and reset > now:
            until, why = reset + RESET_MARGIN, f"resets {stamp(reset)}"
        else:
            until, why = now + backoff, f"no reset time given, backing off {backoff}s"
            backoff = min(backoff * 2, BACKOFF_CAP)
        w = {"step": label, "kind": hit["kind"], "reason": hit["reason"][:200], "why": why,
             "at": stamp(now), "until": stamp(until), "seconds": round(until - now)}
        waits.append(w)
        with open(out_dir / "waits.jsonl", "a") as f:
            f.write(json.dumps(w) + "\n")
        log(f"{time.strftime('%H:%M')} {out_dir.name} {label}: {hit['kind']} limit, waiting until {w['until']}"
            f" ({w['seconds']}s, {why}): {w['reason'][:120]}")
        SLEEP(max(0, until - now))
        status, said = PROBE()
        if status == "ok":
            log(f"{time.strftime('%H:%M')} {out_dir.name} {label}: the probe went through, redoing the step")
            return waits
        if status == "limited":
            hit, reset, failed = said, said["reset"], 0
            continue
        failed += 1
        if failed >= 3:
            raise RoundStop(f"{label}: the probe failed {failed} times, and not on a limit: {said}")


def attempt_usage(text):
    """An attempt's tokens and turns: its result's, or, cut off before one, its messages' summed."""
    objs, _ = json_lines(text)
    result = next((o for o in reversed(objs) if o.get("type") == "result"), None)
    if result:
        u, turns = result.get("usage", {}), result.get("num_turns")
    else:
        msgs = {o["message"].get("id"): o["message"].get("usage", {}) for o in objs
                if o.get("type") == "assistant" and not o.get("parent_tool_use_id") and o.get("message")}
        u = {k: sum(m.get(k, 0) for m in msgs.values()) for k in
             ("input_tokens", "output_tokens", "cache_read_input_tokens", "cache_creation_input_tokens")}
        turns = len(msgs)
    return {"tokens": {"input": u.get("input_tokens", 0), "output": u.get("output_tokens", 0),
                       "cache_read": u.get("cache_read_input_tokens", 0),
                       "cache_write": u.get("cache_creation_input_tokens", 0)}, "turns": turns}


def pre(ws):
    """Where a run's snapshot of the moment before its next agent call lives."""
    return ws.parent / f"{ws.name}.pre"


def session_dir(ws):
    return Path.home() / ".claude" / "projects" / session_key(ws)


def hook_files(env, sid):
    """The hooks' per-session state (hooks/lib.sh session_file: touched, stop-blocks, stop-green,
    bigread, shell-edits, each call's format mark; arm H's menard-h-shell-)."""
    if not sid:
        return []
    return sorted(Path(env.get("TMPDIR") or "/tmp").glob(f"menard-*{re.sub(r'[^A-Za-z0-9_-]', '', sid)}*"))


def rm(path):
    shutil.rmtree(path, ignore_errors=True)
    if path.exists():
        subprocess.run(["chmod", "-R", "u+w", str(path)], check=False)
        shutil.rmtree(path)


def new_progress(resumable):
    return {"resumable": resumable, "point": None, "steps": [], "sid": None, "spent": 0.0, "wall_s": 0.0,
            "interrupted": [], "waits": [], "resumes": [], "_mark": time.time(), "_paused": 0.0}


def save_progress(snap, progress):
    if progress["resumable"]:
        (snap / "progress.json.tmp").write_text(json.dumps({k: v for k, v in progress.items() if not k.startswith("_")}))
        (snap / "progress.json.tmp").rename(snap / "progress.json")


def checkpoint(ws, env, progress, point):
    """Snapshot the moment before an agent call: the workspace (reflinked, as the check snapshot), the
    session's files under ~/.claude/projects and its hook state in TMPDIR, with the run's progress
    (resumable runs) written last. Built beside the last one and swapped in, so a kill at any moment
    leaves one whole."""
    progress["wall_s"] += time.time() - progress["_mark"] - progress["_paused"]
    progress["point"] = point
    snap, new = pre(ws), ws.parent / f"{ws.name}.pre.new"
    rm(new)
    new.mkdir(parents=True)
    subprocess.run(["cp", "-a", "--reflink=auto", str(ws), str(new / "ws")], check=True)
    if session_dir(ws).exists():
        subprocess.run(["cp", "-a", "--reflink=auto", str(session_dir(ws)), str(new / "session")], check=True)
    (new / "tmp").mkdir()
    for f in hook_files(env, progress["sid"]):
        shutil.copy2(f, new / "tmp" / f.name)
    save_progress(new, progress)
    rm(snap)
    new.rename(snap)
    progress["_mark"], progress["_paused"] = time.time(), 0.0
    return snap


def restore(snap, ws, env, sids):
    """Put the workspace, the session files and the hook state of `sids` back as `snap` holds them."""
    kill_stragglers(ws)
    rm(ws)
    subprocess.run(["cp", "-a", "--reflink=auto", str(snap / "ws"), str(ws)], check=True)
    rm(session_dir(ws))
    if (snap / "session").exists():
        session_dir(ws).parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["cp", "-a", "--reflink=auto", str(snap / "session"), str(session_dir(ws))], check=True)
    for sid in set(filter(None, sids)):
        for f in hook_files(env, sid):
            f.unlink()
    tmp = Path(env.get("TMPDIR") or "/tmp")
    for f in (snap / "tmp").iterdir():
        shutil.copy2(f, tmp / f.name)


def resume_point(ws):
    """(snapshot, progress) a killed runner left for this run, or None. The newer one first: a kill
    between writing it and swapping it in leaves both."""
    for snap in (ws.parent / f"{ws.name}.pre.new", pre(ws)):
        if (snap / "progress.json").exists():
            progress = json.loads((snap / "progress.json").read_text())
            return snap, dict(progress, _mark=time.time(), _paused=0.0)
    return None


def drop_stale_traces(out_dir, rid, point):
    """The traces a killed runner wrote at or past `point` (steps sort by name, then CI rounds)."""
    for t in (out_dir / "traces").glob(f"{rid}.*.jsonl"):
        part = t.name[len(rid) + 1:-len(".jsonl")]
        if part.startswith("ci"):
            stale = not point.startswith("ci") or int(part[2:]) >= int(point[2:])
        else:
            stale = point != "post" and not point.startswith("ci") and part >= point
        if stale:
            t.unlink()


def agent_turn(cmd, ws, trace, env, snap, label, progress, out_dir):
    """run_agent, and when the API's limit rather than the agent ended it: the attempt kept aside as
    `<trace>.interruptedN.log` with its tokens under progress["interrupted"] (not the step's), the
    limit waited out, the run put back as `snap` holds it (the suite's cleanup too: its databases and
    tmux, as a resumed run starts), and the same call again, MAX_REDOS times at most.
    (timed_out, start) of the attempt that counts."""
    for attempt in range(1, MAX_REDOS + 1):
        started = time.time()
        with open(trace, "w") as f:
            timed_out = run_agent(cmd, ws, f, env)
        hit = limit_death(trace.read_text())
        if not hit:
            return timed_out, started
        kept = trace.with_name(f"{trace.name.removesuffix('.jsonl')}.interrupted{len(progress['interrupted']) + 1}.log")
        trace.rename(kept)
        progress["interrupted"].append({"step": label, **attempt_usage(kept.read_text()), "at": stamp(CLOCK()),
                                        "kind": hit["kind"], "reason": hit["reason"][:200], "trace": kept.name})
        save_progress(snap, progress)
        if attempt == MAX_REDOS:
            break
        progress["waits"] += wait_out(hit, out_dir, label)
        if CURRENT:
            cleanup(*CURRENT)
        restore(snap, ws, env, [hit["session_id"], progress["sid"]])
        progress["_paused"] += time.time() - started
        save_progress(snap, progress)
    raise RoundStop(f"{label}: the API's limit ended it {MAX_REDOS} times ({hit['reason'][:150]});"
                    f" the round stops here, and the same command resumes it")


def check(check_dir, ws, run_env=None):
    """check.sh in check_dir, run in ws after its hidden/ files are copied in, under the run's env."""
    hidden = check_dir / "hidden"
    if hidden.exists():
        shutil.copytree(hidden, ws, dirs_exist_ok=True)
    code, out = sh(["bash", str(check_dir / "check.sh")], ws, timeout=1800,
                   env=dict(run_env or os.environ, CASE_DIR=str(check_dir),
                            EVAL_COMMON=str(EVAL / "cases" / "common.sh"), MIX_ENV="test"))
    return code, out


def run_steps(case_dir, arm, model, rid, ws, out_dir, env, progress):
    """A long case: steps/NN/prompt.md, each resuming the session the step before left, each with
    its own check.sh, run on a copy of the workspace so its hidden files never reach the agent. Each
    starts from a checkpoint (the steps before it in `progress`), which a limit's redo and a
    killed runner's resume both start from."""
    steps, sid, spent = progress["steps"], progress["sid"], progress["spent"]
    for step in sorted(p for p in (case_dir / "steps").iterdir() if (p / "prompt.md").exists())[len(steps):]:
        trace = out_dir / "traces" / f"{rid}.{step.name}.jsonl"
        before = checkpoint(ws, env, progress, step.name)
        cmd = claude_cmd((step / "prompt.md").read_text().strip(), model, arm, resume=sid, persist=True)
        timed_out, t0 = agent_turn(cmd, ws, trace, env, before, step.name, progress, out_dir)
        # the agent's own wall, apart from the grading after it (~200 s a session in focus2)
        agent_wall = round(time.time() - t0, 1)
        m = trace_metrics(trace, ws)
        sid = progress["sid"] = m["session_id"] or sid
        # a resumed session's total_cost_usd is the whole session's so far; turns and tokens are this call's
        if m["cost_usd"] is not None:
            m["cost_usd"], spent = m["cost_usd"] - spent, m["cost_usd"]
            progress["spent"] = spent
        # the tree as the step left it: desk1's steps that were red and green by the next could not be
        # looked into, with only the session's last diff kept
        (out_dir / "traces" / f"{rid}.{step.name}.diff").write_text(diff_metrics(ws, [])[1])
        snap = ws.parent / f"{ws.name}.check"
        shutil.rmtree(snap, ignore_errors=True)
        subprocess.run(["cp", "-a", "--reflink=auto", str(ws), str(snap)], check=True)
        # the run's env: a real project's check needs its throwaway databases (eval/tlon), not the defaults
        code, out = check(step, snap, env)
        shutil.rmtree(snap, ignore_errors=True)
        steps.append({"step": step.name, "pass": code == 0, "check": out.strip()[-400:],
                      "formatted": "NOTE: unformatted" not in out, "wall_s": round(time.time() - t0, 1),
                      "agent_wall_s": agent_wall, "timed_out": timed_out, **m})
        if timed_out or not sid:
            break
    return steps, sid


def ci_loop(case_dir, arm, model, rid, ws, out_dir, env, sid, steps, progress):
    """CI as the project runs it (the case's `ci` file), once the agent says it is done. Red, the
    failure goes back to the same session, twice at most: the tokens to a mergeable change, not to
    the agent's stop. An agent that left files unformatted "finished" cheaper than it was. Each turn
    back starts from a checkpoint, as a step does; resumed at one (`ci_next`: its round and the
    failure it was told), CI is not run again for it."""
    ci = progress.get("ci") or {"green_first": None, "green": None, "rounds": 0, "turns": 0,
                                "tokens": {"input": 0, "output": 0, "cache_read": 0, "cache_write": 0}}
    if not (case_dir / "ci").exists() or not sid or not steps or steps[-1]["timed_out"]:
        return ci
    resumed = progress.pop("ci_next", None)
    for attempt in range(resumed[0] if resumed else 0, 3):
        if resumed:
            failed, resumed = resumed[1], None
        else:
            code, out = sh((case_dir / "ci").read_text().strip(), ws, timeout=900, env=env)
            ci["green_first"] = code == 0 if attempt == 0 else ci["green_first"]
            ci["green"] = code == 0
            if code == 0 or attempt == 2:
                break
            failed = "\n".join(out.strip().splitlines()[-60:])
        progress["ci"], progress["ci_next"] = ci, [attempt, failed]
        before = checkpoint(ws, env, progress, f"ci{attempt + 1}")
        trace = out_dir / "traces" / f"{rid}.ci{attempt + 1}.jsonl"
        agent_turn(claude_cmd(f"CI failed on your change:\n\n{failed}\n\nFix it so CI passes.", model, arm,
                              resume=sid, persist=True), ws, trace, env, before, f"ci{attempt + 1}", progress, out_dir)
        del progress["ci_next"]
        m = trace_metrics(trace, ws)
        sid = progress["sid"] = m["session_id"] or sid
        ci["rounds"] += 1
        ci["turns"] += m["turns"] or 0
        for k in ci["tokens"]:
            ci["tokens"][k] += m["tokens"][k]
    return ci


def run_one(case_dir, arm, model, n, out_dir):
    rid = f"{case_dir.name}.{arm}.{model}.{n}"
    ws = WORK / "runs" / out_dir.name / rid
    (out_dir / "traces").mkdir(parents=True, exist_ok=True)
    # a long run a killed runner left half done goes on from its last checkpoint; anything else anew
    long = (case_dir / "steps").exists()
    got = resume_point(ws) if long else None
    if got:
        snap, progress = got
        restore(snap, ws, os.environ, [progress["sid"]])
        drop_stale_traces(out_dir, rid, progress["point"])
        progress["resumes"].append({"at": stamp(time.time()), "point": progress["point"]})
        log(f"{time.strftime('%H:%M')} {out_dir.name} {rid}: resumed at {progress['point']}")
    else:
        if long and traces_of(out_dir, rid):
            log(f"{time.strftime('%H:%M')} {out_dir.name} {rid}: no checkpoint left to resume from, redone from the start")
        prepare(case_dir, ws, arm)
        progress = new_progress(long)
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
    if long:
        return run_long(case_dir, arm, model, n, rid, ws, out_dir, env, progress)
    prompt = (case_dir / "prompt.md").read_text().strip()
    trace = out_dir / "traces" / f"{rid}.jsonl"
    before = checkpoint(ws, env, progress, "agent")
    timed_out, t0 = agent_turn(claude_cmd(prompt, model, arm), ws, trace, env, before, "agent", progress, out_dir)
    wall = round(time.time() - t0, 1)

    allowed = [g.strip() for g in (case_dir / "allowed").read_text().splitlines() if g.strip()] \
        if (case_dir / "allowed").exists() else []
    diff, patch = diff_metrics(ws, allowed)
    (out_dir / "traces" / f"{rid}.diff").write_text(patch)
    code, check_out = check(case_dir, ws, env)
    cleanup(case_dir, rid, ws, env)
    row = {
        "id": rid, "case": case_dir.name, "kind": (case_dir / "kind").read_text().strip() if (case_dir / "kind").exists() else "",
        "arm": arm, "model": model, "effort": EFFORT, "seed": SEED, "basis": BASIS, "menard": pinned(arm), "n": n, "wall_s": wall, "agent_wall_s": wall,
        "timed_out": timed_out,
        "pass": code == 0, "check": check_out.strip()[-800:],
        "formatted": "NOTE: unformatted" not in check_out,
        "clean": code == 0 and not diff["noise_files"] and "NOTE: unformatted" not in check_out, **diff, **trace_metrics(trace, ws),
        **lint(ws, env, out_dir, rid), "interrupted": progress["interrupted"], "waits": progress["waits"],
    }
    with open(out_dir / "runs.jsonl", "a") as f:
        f.write(json.dumps(row) + "\n")
    remove_workspace(ws)
    rm(pre(ws))
    return row


def run_long(case_dir, arm, model, n, rid, ws, out_dir, env, progress):
    """One row for a whole session: its steps' sums, and each step under `steps`. The diff, credo
    and the habits are the agent's, taken as it stopped and before the CI loop, like pass and clean;
    what CI's rounds changed on top is under `ci.after`. Resumed, it goes on from `progress`."""
    if not progress.get("steps_done"):
        run_steps(case_dir, arm, model, rid, ws, out_dir, env, progress)
        progress["steps_done"] = True
    steps, sid = progress["steps"], progress["sid"]
    allowed = [g.strip() for g in (case_dir / "allowed").read_text().splitlines() if g.strip()] \
        if (case_dir / "allowed").exists() else []
    # the agent's diff and lint as it stopped, kept for a resume inside the CI loop, which changes both
    if "post" not in progress:
        checkpoint(ws, env, progress, "post")
        diff, patch = diff_metrics(ws, allowed)
        (out_dir / "traces" / f"{rid}.diff").write_text(patch)
        progress["post"] = {"diff": diff, "linted": lint(ws, env, out_dir, rid)}
    diff, linted = progress["post"]["diff"], progress["post"]["linted"]
    ci = ci_loop(case_dir, arm, model, rid, ws, out_dir, env, sid, steps, progress)
    if ci["rounds"]:
        after, patch = diff_metrics(ws, allowed)
        (out_dir / "traces" / f"{rid}.ci.diff").write_text(patch)
        ci["after"] = {k: after[k] for k in ("files", "lines_changed", "noise_files")}
        ci["after"]["credo"] = lint(ws, env, out_dir, rid)["credo"]
    total = lambda k: sum(s[k] or 0 for s in steps)
    tokens = {k: sum(s["tokens"][k] for s in steps) for k in ("input", "output", "cache_read", "cache_write")}
    last_ok = bool(steps) and steps[-1]["pass"] and len(steps) == len(list((case_dir / "steps").glob("*/prompt.md")))
    row = {
        "id": rid, "case": case_dir.name, "kind": "long", "arm": arm, "model": model, "effort": EFFORT, "seed": SEED, "basis": BASIS, "menard": pinned(arm), "n": n,
        # the runner's own time on it: no limit's wait, no attempt it cut short, no checkpoint's copy
        "wall_s": round(progress["wall_s"] + time.time() - progress["_mark"] - progress["_paused"], 1),
        "agent_wall_s": round(total("agent_wall_s"), 1),
        "timed_out": any(s["timed_out"] for s in steps),
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
                                      "tool_errors", "red_runs", "wall_s", "agent_wall_s", "timed_out")} for s in steps],
        **linted,
        "ci": ci, "interrupted": progress["interrupted"], "waits": progress["waits"], "resumes": progress["resumes"],
    }
    # after CI and lint, which need the run's databases: a long session left them all behind
    cleanup(case_dir, rid, ws, env)
    with open(out_dir / "runs.jsonl", "a") as f:
        f.write(json.dumps(row) + "\n")
    remove_workspace(ws)
    rm(pre(ws))
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
    ap.add_argument("--arms", default="", help="a comma list of without, with, with-narrow, with-full; by default "
                    "without and with. without runs only for a case and model with fewer than --runs baseline rows on this basis")
    ap.add_argument("--models", default="claude-sonnet-5")
    ap.add_argument("--runs", type=int, default=1)
    ap.add_argument("--rebuild", action="store_true")
    ap.add_argument("--effort", default="", help="low|medium|high|xhigh|max, passed to claude")
    ap.add_argument("--suite", default=str(EVAL), help="a dir holding fixture/ and cases/")
    ap.add_argument("--stop-at", default="", help="HH:MM local; start no run after it")
    ap.add_argument("--seed", type=int, default=None, help="the arm order's seed (default: drawn, and kept in results/ROUND/seed)")
    a = ap.parse_args()
    unknown = [arm for arm in a.arms.split(",") if arm and arm not in ARMS]
    if unknown:
        sys.exit(f"no arm {', '.join(unknown)}: the arms are {' and '.join(ARMS)}")
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
    cases = sorted(p.parent for p in [*(suite / "cases").glob("*/prompt.md"), *(suite / "cases").glob("*/steps")])
    if a.cases:
        want = a.cases.split(",")
        cases = [c for c in cases if any(fnmatch.fnmatch(c.name, w) for w in want)]
    out_dir = EVAL / "results" / a.round
    out_dir.mkdir(parents=True, exist_ok=True)
    done = set()
    if (out_dir / "runs.jsonl").exists():
        done = {json.loads(l)["id"] for l in (out_dir / "runs.jsonl").read_text().splitlines() if l.strip()}

    global BASIS
    BASIS = basis(suite)
    log(f"{time.strftime('%H:%M')} {a.round} basis: agent {BASIS['agent']}, graders {BASIS['graders']}, {BASIS['claude']}")

    # the round's seed: given, kept from its first start (a resumed round keeps its order), or drawn
    global SEED
    seed_file = out_dir / "seed"
    SEED = a.seed if a.seed is not None else int(seed_file.read_text()) if seed_file.exists() else random.randrange(1 << 32)
    seed_file.write_text(f"{SEED}\n")
    log(f"{time.strftime('%H:%M')} {a.round} seed={SEED} arms={a.arms or 'with, and without where there is no baseline'}")
    arms = a.arms.split(",") if a.arms else ["without", "with"]
    # without is a baseline: run where this basis has too few of it, not at every round
    kept = {}
    for case in cases:
        for model in a.models.split(","):
            # lent to any round that runs without, named or by default: a variant is judged against it too
            kept[(case.name, model)] = len(baseline(case.name, model, BASIS)) if "without" in arms else 0
            if kept[(case.name, model)] >= a.runs:
                log(f"{time.strftime('%H:%M')} {a.round} {case.name} {model}: without is the baseline, "
                    f"{kept[(case.name, model)]} rows on this basis")
    for case, arm, model, n in schedule(cases, arms, a.models.split(","), a.runs, SEED):
        rid = f"{case.name}.{arm}.{model}.{n}"
        if rid in done:
            continue
        # the baseline is topped up to --runs, not run --runs times again: n counts from 1 in every
        # round, so a round with one baseline row lent runs n=1 and skips the rest
        if arm == "without" and kept[(case.name, model)] + n > a.runs:
            continue
        if a.stop_at and time.strftime("%H:%M") >= a.stop_at:
            print(f"stop-at {a.stop_at} reached", flush=True)
            return
        try:
            row = run_one(case, arm, model, n, out_dir)
        except RoundStop as e:
            # its databases and workspace go as a finished run's do; its checkpoint stays to resume from
            case_dir, rid, ws, env = CURRENT
            cleanup(case_dir, rid, ws, env)
            remove_workspace(ws)
            log(f"{time.strftime('%H:%M')} {a.round} STOPPED: {e}")
            sys.exit(75)
        line = (f"{time.strftime('%H:%M')} {a.round} {rid}: {'PASS' if row['pass'] else 'FAIL'}"
                f"{'' if row['clean'] or not row['pass'] else ' (noisy)'} turns={row['turns']}"
                f" cost={row['cost_usd']:.3f} wall={row['wall_s']}s tool_errors={row['tool_errors']} red_runs={row['red_runs']}")
        log(line, f"tools={row['tools']}")


def schedule(cases, arms, models, runs, seed):
    """Every (case, arm, model, n) in the order they run: run by run, model by model, case by case,
    and within each the arms in an order `seed` shuffles, so no arm always goes first (wall time and
    the prompt cache's warmth followed the arm that always went first) while drift in the API over the
    window still hits every arm alike. The same seed gives the same order."""
    rng = random.Random(seed)
    out = []
    for n in range(1, runs + 1):
        for model in models:
            for case in cases:
                order = list(arms)
                rng.shuffle(order)
                out += [(case, arm, model, n) for arm in order]
    return out


def log(line, *more):
    """One line to stdout and to results/live.log, one file across rounds, what a watcher tails."""
    print(line, *more, flush=True)
    with open(EVAL / "results" / "live.log", "a") as f:
        f.write(line + "\n")


if __name__ == "__main__":
    main()
