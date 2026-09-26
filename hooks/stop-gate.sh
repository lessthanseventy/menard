#!/usr/bin/env bash
# Stop: before the agent ends its turn, the gate of every project it wrote Elixir into (the format
# hook keeps the list). Red, the stop is refused with the failures, and the agent fixes them while
# its context is warm, not in a CI round trip after. The eval (focus1): 6 of 7 sessions never ran
# the gate; the one that did was told to by manos' instructions.
set -uo pipefail

payload=$(cat)
session=$(jq -r '.session_id // "none"' <<<"$payload")
session=${session//[^A-Za-z0-9_-]/}
touched="${TMPDIR:-/tmp}/menard-touched-$session"
blocks="${TMPDIR:-/tmp}/menard-stop-blocks-$session"
[[ -s "$touched" ]] || exit 0

# three refusals at most: a gate the agent cannot turn green must not hold the session forever
count=$(cat "$blocks" 2>/dev/null || echo 0)
((count < 3)) || exit 0

red=""
while IFS= read -r dir; do
  out=$("${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/..}/bin/menard" run check --in "$dir" 2>/dev/null </dev/null)
  [[ "$out" == *'"ok":true'* ]] && continue
  why=$(jq -r '(.failures // [])[:15][] | "  \(.kind) \(.at // "") \(.message | split("\n")[0])"' <<<"$out" 2>/dev/null)
  [[ -n "$why" ]] || why=$(jq -r '.tail // "  (no detail)"' <<<"$out" 2>/dev/null | tail -12)
  red+="${dir}:"$'\n'"${why}"$'\n'
done < <(sort -u "$touched")

[[ -n "$red" ]] || exit 0
echo $((count + 1)) >"$blocks"
jq -n --arg r "The project's gate (what CI runs) is red after your changes:"$'\n'"${red}Fix these, then finish." \
  '{decision: "block", reason: $r}'
