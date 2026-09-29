#!/usr/bin/env python3
"""Aggregate eval/results/ROUND*/runs.jsonl into eval/REPORT.md.

    eval/report.py round1 [round2 …]

A cell is a few runs, so a mean alone misleads (at n=3 one step moves an arm's mean 30%): every
number is the median with its range, a rate is k/n, and the arms are compared PAIRED on the same
(case, model, n), where the sign of the delta is the evidence.
"""

import json
import re
import statistics as st
import sys
from collections import defaultdict
from pathlib import Path

EVAL = Path(__file__).resolve().parent
ARMS = ["without", "with", "A", "B", "hook", "run-cli", "compile", "big-read", "stop", "all", "cli", "grep", "map", "map-mcp", "lazy-mcp", "M", "H", "L", "C"]
ARM_TEXT = {
    "without": "Claude Code and nothing else",
    "with": "the menard plugin as a user installs it: its hooks, MCP tools and skill",
    # the arms of the rounds before the two-arm runner (2026-09-28), kept to read their rows
    "A": "no menard",
    # B is menard as shipped at the round's commit: through bench5 the MCP tools, the guard hook and
    # the skill; from bench6 the formatting hook alone (69059a4)
    "B": "menard as shipped (bench1-5: MCP tools, guard hook, skill; bench6 on: the formatting hook)",
    "M": "menard's hook plus manos (the MCP tools and their skill)",
    "hook": "menard as it ships: the formatting hook (B from bench6 on)",
    "run-cli": "hook, plus a few lines at session start teaching `menard run test` / `run check` (one JSON line per run)",
    "compile": "hook, plus a compile after each write naming compiler warnings in the files written",
    "big-read": "hook, plus a whole-file Read of an Elixir file over 800 lines answered with its outline (once)",
    "all": "all of menard: hook, run-cli, compile, big-read, stop and the guard together, and manos' tools",
    "stop": "hook, plus a Stop hook that checks what the agent changed (compile, credo on its lines, the stale tests) and refuses the stop while it is red, and the whole gate before a git commit (until 2026-09-26: the whole gate at every stop)",
    "map-mcp": "hook, plus the full map and manos (its MCP tools, always loaded)",
    "cli": "hook, plus a few lines at session start teaching menard's CLI (rename, find, outline)",
    "grep": "hook, plus each Elixir grep hit's enclosing function",
    "map": "hook, plus a map of the project's modules and public functions at session start",
    "lazy-mcp": "hook, plus manos with its tools loaded on demand (behind ToolSearch) and routing instructions",
    "H": "only the format-and-parse-check hook",
    "L": "B with its MCP tools always loaded",
    "C": "menard without its hooks",
}
MODELS = ["claude-haiku-4-5", "claude-sonnet-5", "claude-opus-5-5", "claude-fable-5-1"]


def load(rounds):
    rows = []
    for r in rounds:
        f = EVAL / "results" / r / "runs.jsonl"
        rows += [dict(json.loads(l), round=r) for l in open(f) if l.strip()]
    return rows + borrowed(rows, rounds)


def borrowed(rows, rounds):
    """The baseline of a round that ran no `without`: the `without` rows of other rounds measured on
    the same start (what a session met and the Claude Code, run.basis), for the same case and model.
    Marked `borrowed`: they ran at another time, so they pair with no row here."""
    out = []
    start = lambda b: json.dumps([(b or {}).get("agent"), (b or {}).get("claude")])
    cells = {(r["case"], r["model"], start(r["basis"])) for r in rows if (r.get("basis") or {}).get("agent")}
    have = {(r["case"], r["model"]) for r in rows if r["arm"] == "without"}
    for f in sorted((EVAL / "results").glob("*/runs.jsonl")):
        if f.parent.name in rounds:
            continue
        for l in open(f):
            r = json.loads(l) if l.strip() else {}
            cell = (r.get("case"), r.get("model"), start(r.get("basis")))
            if r.get("arm") == "without" and cell in cells and cell[:2] not in have:
                out.append(dict(r, round=f.parent.name, borrowed=True))
    return out


def to_green(r):
    """New input + output until CI was green, the rounds of fixing it included; None without a CI."""
    ci = r.get("ci") or {}
    if ci.get("green_first") is None:
        return None
    t, c = r["tokens"], ci["tokens"]
    return t["input"] + t["cache_write"] + t["output"] + c["input"] + c["cache_write"] + c["output"]


# the numbers a run has, each (column label, value of a row, format). Tokens, not dollars: on a
# subscription the meter is usage. Kept apart because a cache read costs a tenth of new input on any
# meter, and one total would hide which one grew
METRICS = {
    "new": ("new in tok", lambda r: r["tokens"]["input"] + r["tokens"]["cache_write"], "{:,.0f}"),
    "cached": ("cached in tok", lambda r: r["tokens"]["cache_read"], "{:,.0f}"),
    "out": ("out tok", lambda r: r["tokens"]["output"], "{:,.0f}"),
    "turns": ("turns", lambda r: r["turns"], "{:.0f}"),
    "wall": ("wall s", lambda r: r["wall_s"], "{:.0f}"),
    # the agent's own wall, apart from the grading (rows before 2026-09-26 have only wall_s)
    "agent": ("agent s", lambda r: r.get("agent_wall_s"), "{:.0f}"),
    # calls the tool refused; rows before 2026-09-26 counted red test runs in (`failed_calls`)
    "failed": ("tool errors", lambda r: r.get("tool_errors", r.get("failed_calls")), "{:.0f}"),
    "red": ("red runs", lambda r: r.get("red_runs"), "{:.0f}"),
    "rereads": ("rereads", lambda r: r.get("rereads"), "{:.0f}"),
    # what CI would still catch: credo issues left (None where the fixture has no credo)
    "credo": ("credo left", lambda r: r.get("credo"), "{:.0f}"),
    "reruns": ("reruns", lambda r: r.get("reruns"), "{:.0f}"),
    "to_green": ("tok to green", to_green, "{:,.0f}"),
}
# the yes/no a run has, shown as k/n
FLAGS = {"pass": "pass", "clean": "clean", "ran_gate": "ran gate", "ci_first": "CI green 1st"}
TABLE = ["new", "cached", "out", "turns", "wall", "agent", "failed", "red", "credo", "reruns", "to_green"]


def flag(r, key):
    if key == "ci_first":
        return (r.get("ci") or {}).get("green_first")
    return r.get(key)


def spread(xs, fmt="{:.1f}"):
    """The median with its range over the runs, `m (lo–hi)`, or the one value there is."""
    xs = [x for x in xs if x is not None]
    if not xs:
        return "–"
    if len(xs) == 1:
        return fmt.format(xs[0])
    return f"{fmt.format(st.median(xs))} ({fmt.format(min(xs))}–{fmt.format(max(xs))})"


def kofn(rows, key):
    """`k/n` of the rows where `key` holds, over the rows that have it."""
    have = [r for r in rows if flag(r, key) is not None]
    return f"{sum(1 for r in have if flag(r, key))}/{len(have)}" if have else "–"


def unbalanced(rows):
    """The (case, model) cells whose arms ran a different number of times: a mean over them
    compares different tasks. [(cell, {arm: n})]."""
    counts = defaultdict(lambda: defaultdict(int))
    for r in rows:
        counts[(r["case"], r["model"])][r["arm"]] += 1
    return [(key, dict(c)) for key, c in sorted(counts.items()) if len(set(c.values())) > 1]


def base_of(rows):
    """The arm the others are read against: `without`, or A in the rounds before it had that name."""
    return "without" if any(r["arm"] == "without" for r in rows) else "A"


def paired(rows, base=None):
    """Each arm against `base` on the same (case, model, n), the run that differs only by the arm:
    per metric the cells where the arm was lower / higher and the delta's median and range, and
    the pass outcomes side by side. An unmatched run pairs with nothing."""
    base = base or base_of(rows)
    cells = defaultdict(dict)
    for r in rows:
        # a borrowed baseline ran at another time: compared arm against arm, paired with nothing
        if not r.get("borrowed"):
            cells[(r["case"], r["model"], r["n"])][r["arm"]] = r
    out = {}
    for arm in sorted({r["arm"] for r in rows} - {base}, key=lambda a: ARMS.index(a) if a in ARMS else 99):
        pairs = [(c[arm], c[base]) for c in cells.values() if arm in c and base in c]
        if not pairs:
            continue
        metrics = {}
        for key in ("new", "out", "turns", "wall", "agent", "red", "reruns"):
            f = METRICS[key][1]
            ds = [f(a) - f(b) for a, b in pairs if f(a) is not None and f(b) is not None]
            if ds:
                metrics[key] = {"n": len(ds), "lower": sum(d < 0 for d in ds), "higher": sum(d > 0 for d in ds),
                                "median": st.median(ds), "min": min(ds), "max": max(ds)}
        passes = {"arm_only": 0, "base_only": 0, "both": 0, "neither": 0}
        for a, b in pairs:
            passes[{(True, False): "arm_only", (False, True): "base_only", (True, True): "both", (False, False): "neither"}
                   [(bool(a["pass"]), bool(b["pass"]))]] += 1
        out[arm] = {"pairs": len(pairs), "metrics": metrics, "pass": passes}
    return out


def paired_table(rows, base=None):
    base = base or base_of(rows)
    p = paired(rows, base)
    if not p:
        return f"(no arm shares a (case, model, n) with {base})"
    out = [f"| arm vs {base} | pairs | pass: arm only / {base} only / both / neither | metric | arm lower / higher | median Δ | min–max Δ |",
           "|---|---|---|---|---|---|---|"]
    for arm, d in p.items():
        ps = d["pass"]
        first = f"| {arm} | {d['pairs']} | {ps['arm_only']} / {ps['base_only']} / {ps['both']} / {ps['neither']} |"
        for key, m in d["metrics"].items():
            label, _, fmt = METRICS[key]
            sign = lambda x: ("+" if x > 0 else "") + fmt.format(x)
            out.append(f"{first} {label} | {m['lower']} / {m['higher']} | {sign(m['median'])} | {sign(m['min'])}…{sign(m['max'])} |")
            first = "| | | |"
    return "\n".join(out)


def usage(r, rounds):
    """What a run reached for, read from its trace when it's still on disk."""
    tools = r["tools"]
    u = {"mcp": any(k.startswith("menard:") for k in tools), "cli": False, "skill": tools.get("Skill", 0) > 0,
         "shell_edit": any(g["kind"] == "shell_edit_ex" for g in r["gaps"]),
         "guard": any(g["kind"] == "guard_block" for g in r["gaps"]), "edit_ex": False}
    for rd in rounds:
        # a long run keeps one trace per step ({id}.01.jsonl …)
        d = EVAL / "results" / rd / "traces"
        traces = [t for t in [d / f"{r['id']}.jsonl"] if t.exists()] + sorted(d.glob(f"{r['id']}.[0-9][0-9].jsonl"))
        if not traces:
            continue
        for line in (line for t in traces for line in open(t)):
            if '"tool_use"' not in line:
                continue
            o = json.loads(line)
            for c in o.get("message", {}).get("content", []):
                if c.get("type") != "tool_use":
                    continue
                inp = c.get("input", {})
                if c["name"] == "Bash" and re.search(r"(^|[\s/;&|(])(menard\s+\w|mix menard\.)", inp.get("command", "")):
                    u["cli"] = True
                if c["name"] in ("Edit", "Write", "MultiEdit") and str(inp.get("file_path", "")).endswith((".ex", ".exs")):
                    u["edit_ex"] = True
        break
    return u


WRITES = {"Edit", "Write", "MultiEdit"}
MENARD_WRITES = {"clause", "stmt", "block", "attr", "directive", "module", "rename", "write"}


def habits(r, rounds):
    """Two costs a trace shows and a row does not: Reads after the run's last edit (an edit through
    the shell too, which is how A edits), and outline on a file already Read whole. And the peak
    context one model call read."""
    import run
    for rd in rounds:
        d = EVAL / "results" / rd / "traces"
        traces = [t for t in [d / f"{r['id']}.jsonl"] if t.exists()] + sorted(d.glob(f"{r['id']}.[0-9][0-9].jsonl"))
        if not traces:
            continue
        calls, ctx = [], {}
        for line in (line for t in traces for line in open(t)):
            if not line.startswith("{"):
                continue
            o = json.loads(line)
            if o.get("type") == "assistant" and not o.get("parent_tool_use_id"):
                u = o["message"].get("usage", {})
                ctx[o["message"].get("id")] = u.get("input_tokens", 0) + u.get("cache_read_input_tokens", 0) + u.get("cache_creation_input_tokens", 0)
                for c in o["message"].get("content", []):
                    if c.get("type") == "tool_use":
                        calls.append((re.sub(r"^mcp__plugin_[\w-]+?_menard__", "m:", c["name"]), c.get("input", {})))
        edits = [i for i, (n, inp) in enumerate(calls)
                 if n in WRITES or (n.startswith("m:") and n[2:] in MENARD_WRITES and inp.get("verb") not in ("get", "list"))
                 or (n == "Bash" and run.shell_edit(inp.get("command", "")))]
        after = sum(1 for n, _ in calls[edits[-1] + 1:] if n == "Read") if edits else 0
        seen, dup = set(), 0
        for n, inp in calls:
            if n == "Read" and not inp.get("limit"):
                seen.add(Path(str(inp.get("file_path"))).name)
            if n == "m:outline" and Path(str(inp.get("file"))).name in seen:
                dup += 1
        return {"reads_after": after, "outline_dup": dup, "peak": max(ctx.values(), default=0)}
    return None


def pct(x):
    return "–" if x is None else f"{x * 100:.0f}%"


def mean(xs):
    xs = [x for x in xs if x is not None]
    return st.mean(xs) if xs else None


def table(groups, key_label):
    out = [f"| {key_label} | arm | n | " + " | ".join(FLAGS[k] for k in ("pass", "clean")) + " | "
           + " | ".join(METRICS[k][0] for k in TABLE) + " | ran gate | CI green 1st |",
           "|---|---|---|" + "---|" * (len(TABLE) + 4)]
    for key, by_arm in groups:
        for arm in ARMS + sorted(a for a in by_arm if a not in ARMS):
            rows = by_arm.get(arm, [])
            if not rows:
                continue
            cells = [spread([METRICS[k][1](r) for r in rows], METRICS[k][2]) for k in TABLE]
            out.append(f"| {key} | {arm} | {len(rows)} | {kofn(rows, 'pass')} | {kofn(rows, 'clean')} | " + " | ".join(cells)
                       + f" | {kofn(rows, 'ran_gate')} | {kofn(rows, 'ci_first')} |")
    return "\n".join(out)


def grouped(rows, keyf):
    g = defaultdict(lambda: defaultdict(list))
    for r in rows:
        g[keyf(r)][r["arm"]].append(r)
    return sorted(g.items())


def step_table(rows):
    """A long case step by step: each (case, model, step, arm) over its runs, so a step where the
    arms part is visible under a session total that hides it."""
    g = defaultdict(lambda: defaultdict(list))
    for r in rows:
        for s in r.get("steps") or []:
            g[(f"{r['case']} · {r['model']}", s["step"])][r["arm"]].append(s)
    if not g:
        return "(no long runs)"
    out = ["| case · model | step | arm | n | pass | turns | new in tok | out tok | agent s | red runs |", "|---|---|---|---|---|---|---|---|---|---|"]
    for (cell, step), by_arm in sorted(g.items()):
        for arm in ARMS + sorted(a for a in by_arm if a not in ARMS):
            ss = by_arm.get(arm, [])
            if not ss:
                continue
            out.append(f"| {cell} | {step} | {arm} | {len(ss)} | {kofn(ss, 'pass')} | {spread([s['turns'] for s in ss], '{:.0f}')} | "
                       f"{spread([s['tokens']['input'] + s['tokens']['cache_write'] for s in ss], '{:,.0f}')} | "
                       f"{spread([s['tokens']['output'] for s in ss], '{:,.0f}')} | "
                       f"{spread([s.get('agent_wall_s') for s in ss], '{:.0f}')} | {spread([s.get('red_runs') for s in ss], '{:.0f}')} |")
    return "\n".join(out)


def render(rows, rounds):
    md = [f"# menard eval report\n\nRounds: {', '.join(rounds)}. {len(rows)} runs. Arms: "
          + ", ".join(f"{a} {ARM_TEXT[a]}" for a in ARMS if any(r["arm"] == a for r in rows)) + ".\n\n"
          "Every number is the median over the cell's runs with its range in brackets; a rate is k/n. "
          "`pass`: the case's check (hidden tests, compile with warnings as errors, task-specific greps). "
          "`clean`: passed, touched only the files the task needs, and `mix format --check-formatted` holds. "
          "Tokens are per run, summed over its model calls: `new in` is input the model had not seen (uncached input + cache writes), "
          "`cached in` is input read from the prompt cache, `out` is output. `wall s` is the run's whole wall, `agent s` the agent's "
          "own (without the grading). `tool errors`: calls the tool refused; `red runs`: test or gate runs that came back red. "
          "`credo left`: credo issues in the project after the run, whose base has none; `reruns`: test runs with no edit since the "
          "one before; `ran gate`: runs where the agent ran precommit, credo or `run check` itself. `CI green 1st`: the project's "
          "CI passed as the agent left it; `tok to green`: new input + output until CI was green, the rounds of fixing it included.\n"]

    bad = unbalanced(rows)
    if bad:
        md.append("**WARNING: unbalanced cells** (an arm ran more times than another on the same case and model; "
                  "the by-arm rows mix tasks unevenly, read the paired deltas):\n")
        md += [f"- {case} · {model}: " + ", ".join(f"{a} {n}" for a, n in sorted(c.items())) for (case, model), c in bad]
        md.append("")

    lent = sorted({r["round"] for r in rows if r.get("borrowed")})
    if lent:
        n = sum(1 for r in rows if r.get("borrowed"))
        md.append(f"**Baseline**: the {n} `without` rows are from {', '.join(lent)}, measured on the same suite and "
                  "Claude Code at another time. Read arm against arm under By arm; nothing here is paired with them.\n")
    judged = sorted({(r.get("basis") or {}).get("graders") or "unknown" for r in rows})
    if len(judged) > 1:
        md.append(f"**WARNING: judged by different graders** ({', '.join(judged)}): the pass, clean and step counts "
                  "below are not comparable until the rounds are regraded (eval/regrade.py). Tokens, turns and times are.\n")
    base = base_of(rows)
    md.append(f"## Paired deltas vs {base}\n\nEach arm against {base} on the same (case, model, n): the sign is the evidence, "
              f"the count of cells where the arm was lower / higher; Δ = arm − {base}.\n\n" + paired_table(rows, base) + "\n")
    md.append("## By arm\n\n" + table(grouped(rows, lambda r: "all"), "") + "\n")
    md.append("## By model\n\n" + table(sorted(grouped(rows, lambda r: r["model"]), key=lambda kv: MODELS.index(kv[0]) if kv[0] in MODELS else 9), "model") + "\n")
    md.append("## By task kind\n\n" + table(grouped(rows, lambda r: r["kind"]), "kind") + "\n")
    md.append("## By task kind and model\n\n" + table(grouped(rows, lambda r: f"{r['kind']} · {r['model']}"), "kind · model") + "\n")
    md.append("## By case\n\n" + table(grouped(rows, lambda r: r["case"]), "case") + "\n")
    md.append("## By step\n\n" + step_table(rows) + "\n")

    fails = [r for r in rows if not r["pass"]]
    md.append("## Failed runs\n")
    for r in sorted(fails, key=lambda r: r["id"]):
        why = r["check"].strip().splitlines()[-1] if r["check"].strip() else "(no output)"
        md.append(f"- `{r['id']}`{' (timed out)' if r['timed_out'] else ''}: {why[:200]}")

    md.append("\n## Tool use by arm\n")
    for arm in ARMS + sorted({r["arm"] for r in rows} - set(ARMS)):
        tot = defaultdict(int)
        n = 0
        for r in rows:
            if r["arm"] == arm:
                n += 1
                for k, v in r["tools"].items():
                    tot[k] += v
        if n:
            md.append(f"- **{arm}** ({n} runs): " + ", ".join(f"{k} {v / n:.1f}" for k, v in sorted(tot.items(), key=lambda kv: -kv[1])))

    md.append("\n## menard adoption (share of runs)\n")
    md.append("MCP: called a menard MCP tool. CLI: ran `menard …` or `mix menard.…` through Bash. "
              "Skill: loaded the menard skill. Shell edit: wrote a .ex/.exs with sed -i, a redirect or a script. "
              "Guard block: an Edit/Write on a .ex/.exs refused by the hook.\n")
    md.append("| arm · model | n | MCP | CLI | Skill | shell edit | guard block | Edit/Write on .ex |")
    md.append("|---|---|---|---|---|---|---|---|")
    g = defaultdict(list)
    for r in rows:
        g[(r["arm"], r["model"])].append(r)
    for (arm, model), rs in sorted(g.items(), key=lambda kv: (kv[0][0], MODELS.index(kv[0][1]) if kv[0][1] in MODELS else 9)):
        u = [usage(r, rounds) for r in rs]
        share = lambda k: pct(mean([1.0 if x[k] else 0.0 for x in u]))
        md.append(f"| {arm} · {model} | {len(rs)} | {share('mcp')} | {share('cli')} | {share('skill')} | {share('shell_edit')} | {share('guard')} | {share('edit_ex')} |")

    md.append("\n## Habits (from the traces)\n")
    md.append("Reads after last edit: Read calls after the run's last edit (by a tool or through the shell). Outline of a Read file: "
              "`outline` on a file the run had already Read whole. Peak context: the most one model call read.\n")
    md.append("| arm · model | n | Reads after last edit /run | outline of a Read file /run | peak context |")
    md.append("|---|---|---|---|---|")
    for (arm, model), rs in sorted(g.items(), key=lambda kv: (kv[0][0], MODELS.index(kv[0][1]) if kv[0][1] in MODELS else 9)):
        hs = [h for h in (habits(r, rounds) for r in rs) if h]
        if hs:
            md.append(f"| {arm} · {model} | {len(hs)} | {spread([h['reads_after'] for h in hs])} | "
                      f"{spread([h['outline_dup'] for h in hs])} | {spread([h['peak'] for h in hs], '{:,.0f}')} |")

    md.append("\n## Gap signals (menard arms)\n")
    kinds = defaultdict(list)
    for r in rows:
        if r["arm"] not in ("A", "without"):
            for g in r["gaps"]:
                kinds[g["kind"]].append((r["id"], g))
    for kind, evs in sorted(kinds.items()):
        md.append(f"\n### {kind} ({len(evs)})\n")
        for rid, g in evs[:40]:
            detail = g.get("command") or g.get("text") or g.get("path")
            md.append(f"- `{rid}`: {str(detail)[:220].replace(chr(10), ' ⏎ ')}")

    md.append("\n## menard tool failures (menard arms)\n")
    for r in rows:
        if r["arm"] not in ("A", "without"):
            for f in r["failures"]:
                if f["tool"].startswith("menard:"):
                    md.append(f"- `{r['id']}` {f['tool']}: {f['text'][:220].replace(chr(10), ' ⏎ ')}")
    return "\n".join(md) + "\n"


def main():
    rounds = sys.argv[1:] or ["round1"]
    rows = load(rounds)
    (EVAL / "REPORT.md").write_text(render(rows, rounds))
    print(f"wrote {EVAL / 'REPORT.md'} from {len(rows)} runs")


if __name__ == "__main__":
    main()
