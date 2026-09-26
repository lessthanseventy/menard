#!/usr/bin/env python3
"""Aggregate eval/results/ROUND*/runs.jsonl into eval/REPORT.md.

    eval/report.py round1 [round2 …]
"""

import json
import re
import statistics as st
import sys
from collections import defaultdict
from pathlib import Path

EVAL = Path(__file__).resolve().parent
ARMS = ["A", "B", "hook", "cli", "grep", "map", "lazy-mcp", "M", "H", "L", "C"]
ARM_TEXT = {
    "A": "no menard",
    # B is menard as shipped at the round's commit: through bench5 the MCP tools, the guard hook and
    # the skill; from bench6 the formatting hook alone (69059a4)
    "B": "menard as shipped (bench1-5: MCP tools, guard hook, skill; bench6 on: the formatting hook)",
    "M": "menard's hook plus manos (the MCP tools and their skill)",
    "hook": "menard as it ships: the formatting hook (B from bench6 on)",
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
        rows += [json.loads(l) for l in open(f) if l.strip()]
    return rows


def ctx_tokens(r):
    t = r["tokens"]
    return t["input"] + t["cache_read"] + t["cache_write"]


def mean(xs):
    xs = [x for x in xs if x is not None]
    return st.mean(xs) if xs else None


def stats(rows):
    return {
        "n": len(rows),
        "pass": mean([1.0 if r["pass"] else 0.0 for r in rows]),
        "clean": mean([1.0 if r["clean"] else 0.0 for r in rows]),
        # tokens, not dollars: on a subscription the meter is usage. Kept apart because a cache read
        # costs a tenth of new input on any meter, and one total would hide which one grew
        "new": mean([r["tokens"]["input"] + r["tokens"]["cache_write"] for r in rows]),
        "cached": mean([r["tokens"]["cache_read"] for r in rows]),
        "out": mean([r["tokens"]["output"] for r in rows]),
        "turns": mean([r["turns"] for r in rows]),
        "wall": mean([r["wall_s"] for r in rows]),
        "failed": mean([r["failed_calls"] for r in rows]),
        "rereads": mean([r["rereads"] for r in rows]),
        # what CI would still catch: credo issues left (None where the fixture has no credo), and
        # whether the agent ran the gate itself before it stopped
        "credo": mean([r.get("credo") for r in rows]),
        "ran_gate": mean([None if "ran_gate" not in r else 1.0 if r["ran_gate"] else 0.0 for r in rows]),
    }


def usage(r, rounds):
    """What a run reached for, read from its trace when it's still on disk."""
    tools = r["tools"]
    u = {"mcp": any(k.startswith("menard:") for k in tools), "cli": False, "skill": tools.get("Skill", 0) > 0,
         "shell_edit": any(g["kind"] == "shell_edit_ex" for g in r["gaps"]),
         "guard": any(g["kind"] == "guard_block" for g in r["gaps"]), "edit_ex": False}
    for rd in rounds:
        t = EVAL / "results" / rd / "traces" / f"{r['id']}.jsonl"
        if not t.exists():
            continue
        for line in open(t):
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
    """Two costs a trace shows and a row does not: Reads after the run's last edit, and outline on a
    file already Read whole. And the peak context one model call read."""
    for rd in rounds:
        t = EVAL / "results" / rd / "traces" / f"{r['id']}.jsonl"
        if not t.exists():
            continue
        calls, ctx = [], {}
        for line in open(t):
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
                 if n in WRITES or (n.startswith("m:") and n[2:] in MENARD_WRITES and inp.get("verb") not in ("get", "list"))]
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


def num(x, fmt="{:.1f}"):
    return "–" if x is None else fmt.format(x)


def table(groups, key_label):
    out = [f"| {key_label} | arm | n | pass | clean | new in tok | cached in tok | out tok | turns | wall s | failed calls | credo left | ran gate |",
           "|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for key, by_arm in groups:
        for arm in ARMS + sorted(a for a in by_arm if a not in ARMS):
            rows = by_arm.get(arm, [])
            if not rows:
                continue
            s = stats(rows)
            out.append(f"| {key} | {arm} | {s['n']} | {pct(s['pass'])} | {pct(s['clean'])} | {num(s['new'], '{:,.0f}')} | "
                       f"{num(s['cached'], '{:,.0f}')} | {num(s['out'], '{:,.0f}')} | {num(s['turns'])} | {num(s['wall'])} | {num(s['failed'])} | "
                       f"{num(s['credo'])} | {pct(s['ran_gate'])} |")
    return "\n".join(out)


def grouped(rows, keyf):
    g = defaultdict(lambda: defaultdict(list))
    for r in rows:
        g[keyf(r)][r["arm"]].append(r)
    return sorted(g.items())


def main():
    rounds = sys.argv[1:] or ["round1"]
    rows = load(rounds)
    md = [f"# menard eval report\n\nRounds: {', '.join(rounds)}. {len(rows)} runs. Arms: "
          + ", ".join(f"{a} {ARM_TEXT[a]}" for a in ARMS if any(r["arm"] == a for r in rows)) + ".\n\n"
          "`pass`: the case's check (hidden tests, compile with warnings as errors, task-specific greps). "
          "`clean`: passed, touched only the files the task needs, and `mix format --check-formatted` holds. "
          "Tokens are per run, summed over its model calls: `new in` is input the model had not seen (uncached input + cache writes), "
          "`cached in` is input read from the prompt cache, `out` is output. `credo left`: credo issues in the "
          "project after the run, whose base has none; `ran gate`: runs where the agent ran precommit, credo or "
          "`run check` itself.\n"]

    md.append("## By arm\n\n" + table(grouped(rows, lambda r: "all"), "") + "\n")
    md.append("## By model\n\n" + table(sorted(grouped(rows, lambda r: r["model"]), key=lambda kv: MODELS.index(kv[0]) if kv[0] in MODELS else 9), "model") + "\n")
    md.append("## By task kind\n\n" + table(grouped(rows, lambda r: r["kind"]), "kind") + "\n")
    md.append("## By task kind and model\n\n" + table(grouped(rows, lambda r: f"{r['kind']} · {r['model']}"), "kind · model") + "\n")
    md.append("## By case\n\n" + table(grouped(rows, lambda r: r["case"]), "case") + "\n")

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
    md.append("Reads after last edit: Read calls after the run's last edit. Outline of a Read file: `outline` on a "
              "file the run had already Read whole. Peak context: the most one model call read.\n")
    md.append("| arm · model | n | Reads after last edit /run | outline of a Read file /run | peak context |")
    md.append("|---|---|---|---|---|")
    for (arm, model), rs in sorted(g.items(), key=lambda kv: (kv[0][0], MODELS.index(kv[0][1]) if kv[0][1] in MODELS else 9)):
        hs = [h for h in (habits(r, rounds) for r in rs) if h]
        if hs:
            md.append(f"| {arm} · {model} | {len(hs)} | {mean([h['reads_after'] for h in hs]):.2f} | "
                      f"{mean([h['outline_dup'] for h in hs]):.2f} | {mean([h['peak'] for h in hs]):,.0f} |")

    md.append("\n## Gap signals (menard arms)\n")
    kinds = defaultdict(list)
    for r in rows:
        if r["arm"] != "A":
            for g in r["gaps"]:
                kinds[g["kind"]].append((r["id"], g))
    for kind, evs in sorted(kinds.items()):
        md.append(f"\n### {kind} ({len(evs)})\n")
        for rid, g in evs[:40]:
            detail = g.get("command") or g.get("text") or g.get("path")
            md.append(f"- `{rid}`: {str(detail)[:220].replace(chr(10), ' ⏎ ')}")

    md.append("\n## menard tool failures (menard arms)\n")
    for r in rows:
        if r["arm"] != "A":
            for f in r["failures"]:
                if f["tool"].startswith("menard:"):
                    md.append(f"- `{r['id']}` {f['tool']}: {f['text'][:220].replace(chr(10), ' ⏎ ')}")

    (EVAL / "REPORT.md").write_text("\n".join(md) + "\n")
    print(f"wrote {EVAL / 'REPORT.md'} from {len(rows)} runs")


if __name__ == "__main__":
    main()
