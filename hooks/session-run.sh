#!/usr/bin/env bash
# SessionStart (eval arm run-cli): menard's run verbs, taught in a few lines. Across 288 of the
# operator's own sessions, 90% of test and gate runs were piped through tail/head/grep and 40% were
# run again with no edit between, to see a different slice of the same failure; and agents ran
# mix format by hand 179 times, on files the hook had already formatted. The project's own notes
# win: a plugin installed once must not overrule the repo's instructions.
set -uo pipefail
m="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/bin/menard"
read -r -d '' ctx <<TEXT
If the project's own notes say how to run its tests, do what they say. Otherwise run tests and the gate with menard, through Bash, from the Elixir project's directory (the full path each time):
- $m run check: the project's gate (its precommit alias), one JSON line: ok, the counts, and every failure with its kind, file:line and message; a failing test adds its name, source, and the assertion's left and right.
- $m run test [FILE[:LINE]]: the same for tests alone.
One run tells you what failed and where: no need to run the suite again through tail or grep to find it.
Every Elixir file you write is already formatted with the project's formatter and credo-checked on the lines you changed, and you are told what changed: no need to run mix format or mix credo yourself.
TEXT
jq -n --arg ctx "$ctx" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
