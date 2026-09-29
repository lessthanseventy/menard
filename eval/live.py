#!/usr/bin/env python3
"""Follow a round as it runs: the newest trace's tool calls, what hooks told the agent, and each
step's end. For a person watching in tmux, not for the report.

    eval/live.py ROUND
"""

import json
import sys
import time
from pathlib import Path

traces = Path(__file__).resolve().parent / "results" / sys.argv[1] / "traces"
current, pos = None, 0

while True:
    found = sorted(traces.glob("*.jsonl"), key=lambda p: p.stat().st_mtime) if traces.exists() else []
    if found and found[-1] != current:
        current, pos = found[-1], 0
        print(f"\n=== {current.stem} ===", flush=True)
    if current is None:
        time.sleep(2)
        continue
    with open(current) as f:
        f.seek(pos)
        lines = f.readlines()
        pos = f.tell()
    for line in lines:
        if not line.startswith("{"):
            continue
        try:
            e = json.loads(line)
        except json.JSONDecodeError:
            continue
        if e.get("type") == "assistant":
            for c in e["message"].get("content", []):
                if c.get("type") == "tool_use":
                    inp = c.get("input", {})
                    what = inp.get("command") or inp.get("file_path") or json.dumps(inp)
                    print(f"  {c['name'].replace('mcp__plugin_menard_menard__', 'menard:')}: {str(what)[:140]}", flush=True)
        elif e.get("subtype") == "hook_response" and (e.get("output") or "").strip():
            try:
                ctx = json.loads(e["output"])["hookSpecificOutput"]["additionalContext"]
            except (ValueError, KeyError, TypeError):
                ctx = e["output"]
            print(f"  [{e.get('hook_name')}] {ctx.splitlines()[0][:140]}", flush=True)
        elif e.get("type") == "result":
            u = e.get("usage", {})
            new = u.get("input_tokens", 0) + u.get("cache_creation_input_tokens", 0)
            print(f"  -- step done: {e.get('num_turns')} turns, tokens new {new:,} cached "
                  f"{u.get('cache_read_input_tokens', 0):,} out {u.get('output_tokens', 0):,}", flush=True)
    time.sleep(1)
