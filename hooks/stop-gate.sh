#!/usr/bin/env bash
# Stop: before the agent ends its turn, each project it wrote Elixir into (the format hook keeps the
# list) is checked on what the session changed: compile with warnings as errors, credo on the lines
# it changed, and the tests its change made stale. Red, the stop is refused with the failures, and
# the agent fixes them while its context is warm. The whole gate is the commit's (commit-gate.sh):
# run at every stop it re-ran the suite at each step of a long session (focus2: 7 gate runs to 3).
# Formatting is not checked here: the format hook formatted every file as it was written.
set -uo pipefail

payload=$(cat)
session=$(jq -r '.session_id // "none"' <<<"$payload")
session=${session//[^A-Za-z0-9_-]/}
touched="${TMPDIR:-/tmp}/menard-touched-$session"
blocks="${TMPDIR:-/tmp}/menard-stop-blocks-$session"
green="${TMPDIR:-/tmp}/menard-stop-green-$session"
[[ -s "$touched" ]] || exit 0

# the format hook adds a line per write: the same count as at the last green stop is nothing new
writes=$(wc -l <"$touched")
[[ "$(cat "$green" 2>/dev/null)" == "$writes" ]] && exit 0

# three refusals at most: a gate the agent cannot turn green must not hold the session forever
count=$(cat "$blocks" 2>/dev/null || echo 0)
((count < 3)) || exit 0

menard="${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/..}/bin/menard"
red=""
while IFS= read -r dir; do
  for verb in "compile" "credo --changed" "test --stale"; do
    # shellcheck disable=SC2086 # the verb's words are its arguments
    out=$("$menard" run $verb --in "$dir" 2>/dev/null </dev/null)
    [[ "$out" == *'"ok":true'* ]] && continue
    why=$(jq -r '(.failures // [])[:15][] | "  \(.kind) \(.at // "") \(.message | split("\n")[0])"' <<<"$out" 2>/dev/null)
    [[ -n "$why" ]] || why=$(jq -r '.tail // "  (no detail)"' <<<"$out" 2>/dev/null | tail -12)
    red+="${dir}:"$'\n'"${why}"$'\n'
    break
  done
done < <(sort -u "$touched")

if [[ -z "$red" ]]; then
  echo "$writes" >"$green"
  exit 0
fi
echo $((count + 1)) >"$blocks"
jq -n --arg r "Checked on what you changed (compile, credo on your lines, the tests it made stale), red:"$'\n'"${red}Fix these, then finish." \
  '{decision: "block", reason: $r}'
