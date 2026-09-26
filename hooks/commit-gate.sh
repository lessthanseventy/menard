#!/usr/bin/env bash
# PreToolUse on Bash: a `git commit` waits for the whole gate (`run check`: the project's precommit)
# of every project the session wrote Elixir into, and is refused while one is red. A Claude hook,
# not a git one: it installs nothing in the host's repo and never stands in a human's way. The
# stop checks only what changed (stop-gate.sh); the commit is where the whole suite runs.
set -uo pipefail

payload=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$payload")
# git, its global options (-C/-c and theirs, quoted too; --no-pager, --git-dir=x, --git-dir x), then
# commit; git after a separator, a quote, a slash or any word (then, env A=1, time, bash -c "…")
arg="(\"[^\"]*\"|'[^']*'|[^[:space:]]+)"
opts="([[:space:]]+(-[Cc][[:space:]]+$arg|--(git-dir|work-tree|namespace)[[:space:]]+$arg|-[^[:space:]]+))*"
grep -qE "(^|[[:space:];&|(\`\"'/])git$opts[[:space:]]+commit([[:space:];&|)\`\"']|\$)" <<<"$cmd" || exit 0

session=$(jq -r '.session_id // "none"' <<<"$payload")
touched="${TMPDIR:-/tmp}/menard-touched-${session//[^A-Za-z0-9_-]/}"
[[ -s "$touched" ]] || exit 0

# the repo the commit lands in: -C's directory when the command names one, else the call's own; a
# project written into in another repo is not this commit's to wait on
cwd=$(jq -r '.cwd // empty' <<<"$payload")
at=${cwd:-$PWD}
if [[ "$cmd" =~ git[[:space:]]+-C[[:space:]]+(\"[^\"]*\"|\'[^\']*\'|[^[:space:]]+) ]]; then
  c=${BASH_REMATCH[1]}
  c=${c#[\"\']}
  c=${c%[\"\']}
  [[ "$c" == /* ]] && at=$c || at="$at/$c"
fi
repo=$(git -C "$at" rev-parse --show-toplevel 2>/dev/null)

err=$(mktemp "${TMPDIR:-/tmp}/menard-err.XXXXXX")
trap 'rm -f "$err"' EXIT
# the gate's own deadline, under the 300s its wiring gives it (eval/run.py): a hook the harness kills
# lets the commit through and leaves its mix test running; `timeout` takes menard's whole group down
deadline=$((SECONDS + 280))
red=""
while IFS= read -r dir; do
  [[ -n "$repo" && "$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" == "$repo" ]] || continue
  # the files as a commit would take them (a git tree, the same for the same files): the very ones a
  # green `run check` already passed are not gated again. Menard.Run.tree/1 and green_stamp/1 write
  # it the same way. focus3: the agent ran the gate, green, and the hook ran it again at the commit.
  git_dir=$(git -C "$dir" rev-parse --absolute-git-dir 2>/dev/null)
  # a scratch index in the git dir: one under a TMPDIR inside the project would be one of its files
  idx="$git_dir/menard-index-$$"
  tree=$(GIT_INDEX_FILE=$idx git -C "$dir" add -A . 2>/dev/null && GIT_INDEX_FILE=$idx git -C "$dir" write-tree 2>/dev/null)
  rm -f "$idx"
  prefix=$(git -C "$dir" rev-parse --show-prefix 2>/dev/null)
  name=${prefix//[^A-Za-z0-9]/-}
  name=${name%-}
  stamp="$git_dir/menard-green-${name:-root}"
  [[ -n "$tree" && "$(cat "$stamp" 2>/dev/null)" == "$tree" ]] && continue
  # the reply is stdout's last line; stderr is kept apart, where a line that says "ok":true is no answer
  reply=$(timeout --kill-after=5 $((deadline > SECONDS ? deadline - SECONDS : 1)) "${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/..}/bin/menard" run check --in "$dir" 2>"$err" </dev/null | tail -n1)
  if (($? == 124)); then
    red+="${dir}:"$'\n'"  menard run check gave no answer within 280s (the gate's deadline) and was stopped"$'\n'
    break
  fi
  jq -e '.ok == true' <<<"$reply" >/dev/null 2>&1 && continue
  why=$(jq -r '(.failures // [])[:15][] | "  \(.kind) \(.at // "") \(.message | split("\n")[0])"' <<<"$reply" 2>/dev/null)
  [[ -n "$why" ]] || why=$(jq -r '.tail // empty' <<<"$reply" 2>/dev/null | tail -12)
  # no answer at all: menard's own refusal or error, which it writes to stderr
  [[ -n "$why" ]] || why=$(tail -12 "$err")
  red+="${dir}:"$'\n'"${why}"$'\n'
done < <(sort -u "$touched")

[[ -n "$red" ]] || exit 0
jq -n --arg r "Not committed: the project's gate (what CI runs) is red:"$'\n'"${red}Fix these, then commit." \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
