#!/usr/bin/env bash
# Stop: before the agent ends its turn, each project it wrote Elixir into (the format hook keeps the
# list) is checked on what the session changed: compile with warnings as errors, credo on the lines
# it changed, and the tests its change made stale. Red, the stop is refused with the failures, and
# the agent fixes them while its context is warm. The whole gate is the commit's (commit-gate.sh):
# run at every stop it re-ran the suite at each step of a long session (focus2: 7 gate runs to 3).
# Formatting is not checked here: the format hook formatted every file as it was written.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

touched=$(session_file touched)
blocks=$(session_file stop-blocks)
green=$(session_file stop-green)
if [[ ! -s "$touched" ]]; then
  echo "stop gate: nothing written this session" >&2
  exit 0
fi

# the format hook adds a line per write: the same count as at the last green stop is nothing new
writes=$(wc -l <"$touched")
if [[ "$(cat "$green" 2>/dev/null)" == "$writes" ]]; then
  echo "stop gate: nothing new since green" >&2
  exit 0
fi

# three refusals at most: a gate the agent cannot turn green must not hold the session forever. The
# stop it lets through starts the count again, so the next step of a long session is gated too.
count=$(cat "$blocks" 2>/dev/null || echo 0)
if ((count >= 3)); then
  rm -f "$blocks"
  echo "stop gate: let through after 3 refusals" >&2
  exit 0
fi

err=$(mktemp "${TMPDIR:-/tmp}/menard-err.XXXXXX")
trap 'rm -f "$err"' EXIT
# the gate's own deadline, under the 300s its wiring gives it (eval/run.py): a hook the harness kills
# lets the stop through and leaves its mix test running; `timeout` takes menard's whole group down
deadline=$((SECONDS + 280))
red=""
declare -A took=()
ran=()
while IFS= read -r dir; do
  for verb in "compile" "credo --changed" "test --stale"; do
    start=$SECONDS
    # the reply is stdout's last line; stderr is kept apart, where a line that says "ok":true is no answer
    # shellcheck disable=SC2086 # the verb's words are its arguments
    reply=$(timeout --kill-after=5 $((deadline > SECONDS ? deadline - SECONDS : 1)) "$menard" run $verb --in "$dir" 2>"$err" </dev/null | tail -n1)
    status=$?
    [[ -v "took[$verb]" ]] || ran+=("$verb")
    took[$verb]=$((${took[$verb]:-0} + SECONDS - start))
    if ((status == 124)); then
      red+="${dir}:"$'\n'"  menard run ${verb} gave no answer within 280s (the gate's deadline) and was stopped"$'\n'
      break 2
    fi
    jq -e '.ok == true' <<<"$reply" >/dev/null 2>&1 && continue
    red+="${dir}:"$'\n'"$(red_lines "$reply" "$err")"$'\n'
    break
  done
done < <(sort -u "$touched")

# one line for the trace on every outcome (stderr at exit 0 reaches no model): a green gate and one
# that never ran looked the same
timings=""
for verb in "${ran[@]}"; do timings+="${timings:+, }$verb ${took[$verb]}s"; done
if [[ -z "$red" ]]; then
  echo "$writes" >"$green"
  rm -f "$blocks"
  echo "stop gate: green in ${SECONDS}s ($timings)" >&2
  exit 0
fi
echo $((count + 1)) >"$blocks"
echo "stop gate: red in ${SECONDS}s ($timings), refusal $((count + 1)) of 3" >&2
jq -n --arg r "Checked on what you changed (compile, credo on your lines, the tests it made stale), red:"$'\n'"${red}Fix these, then finish." \
  '{decision: "block", reason: $r}'
