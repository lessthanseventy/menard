#!/usr/bin/env bash
# SubagentStart: a subagent is given none of what its session was told at SessionStart, so it is
# told the same (Menard.Scripts, Menard.Piped). A command hook, as session-start.sh is, with its
# fallback: menard not built yet says the text from hooks/upfront.txt.
set -uo pipefail
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
payload=$(cat)
limit=()
command -v timeout >/dev/null 2>&1 && limit=(timeout 8)
if said=$(${limit[@]+"${limit[@]}"} "$root/bin/menard" hook <<<"$payload"); then
  printf '%s\n' "$said"
  exit 0
fi

jq -n --rawfile ctx "$root/hooks/upfront.txt" \
  '{hookSpecificOutput: {hookEventName: "SubagentStart", additionalContext: $ctx}}'
