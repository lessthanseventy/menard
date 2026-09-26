#!/usr/bin/env bash
# PreToolUse on Bash: a `git commit` waits for the whole gate (`run check`: the project's precommit)
# of every project the session wrote Elixir into, and is refused while one is red. A Claude hook,
# not a git one: it installs nothing in the host's repo and never stands in a human's way. The
# stop checks only what changed (stop-gate.sh); the commit is where the whole suite runs.
set -uo pipefail

payload=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$payload")
# git, its -C/-c options, then commit, at the start of the command or after && ; | (
grep -qE '(^|[;&|(])[[:space:]]*git([[:space:]]+-[Cc][[:space:]]+[^[:space:]]+)*[[:space:]]+commit([[:space:]]|$)' <<<"$cmd" || exit 0

session=$(jq -r '.session_id // "none"' <<<"$payload")
touched="${TMPDIR:-/tmp}/menard-touched-${session//[^A-Za-z0-9_-]/}"
[[ -s "$touched" ]] || exit 0

red=""
while IFS= read -r dir; do
  out=$("${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/..}/bin/menard" run check --in "$dir" 2>/dev/null </dev/null)
  [[ "$out" == *'"ok":true'* ]] && continue
  why=$(jq -r '(.failures // [])[:15][] | "  \(.kind) \(.at // "") \(.message | split("\n")[0])"' <<<"$out" 2>/dev/null)
  [[ -n "$why" ]] || why=$(jq -r '.tail // "  (no detail)"' <<<"$out" 2>/dev/null | tail -12)
  red+="${dir}:"$'\n'"${why}"$'\n'
done < <(sort -u "$touched")

[[ -n "$red" ]] || exit 0
jq -n --arg r "Not committed: the project's gate (what CI runs) is red:"$'\n'"${red}Fix these, then commit." \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
