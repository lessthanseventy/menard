#!/usr/bin/env bash
# SessionStart (eval arm K): menard's structural verbs through Bash, taught in a few lines. The MCP
# tools cost ~5,600 tokens of schema on every turn (bench6) and were used in 19 runs of 34; a
# command the agent already knows how to run costs these lines once.
set -uo pipefail
m="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/bin/menard"
read -r -d '' ctx <<TEXT
menard is installed at $m. Through Bash, from the project root, where grep and sed guess (the full path each time: a shell variable does not outlive its call):
- $m rename OLD NEW \$(git ls-files '*.ex' '*.exs'): a function, variable or module renamed everywhere; strings and comments left alone.
- $m find calls Mod.fun \$(git ls-files '*.ex' '*.exs'): who calls it, with no hits in strings or comments.
- $m outline FILE: each function's name/arity, head and lines, before reading a big file; $m clause get FILE name/arity reads one.
Everything else: Edit and Write as usual. Every Elixir file written is formatted, and you are told what changed.
TEXT
jq -n --arg ctx "$ctx" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
