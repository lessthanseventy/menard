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
  out=$("${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/..}/bin/menard" run check --in "$dir" 2>&1 </dev/null)
  [[ "$out" == *'"ok":true'* ]] && continue
  why=$(jq -r '(.failures // [])[:15][] | "  \(.kind) \(.at // "") \(.message | split("\n")[0])"' <<<"$out" 2>/dev/null)
  [[ -n "$why" ]] || why=$(jq -r '.tail // empty' <<<"$out" 2>/dev/null | tail -12)
  # no answer at all: menard's own refusal or error, which it writes to stderr
  [[ -n "$why" ]] || why=$(tail -12 <<<"$out")
  red+="${dir}:"$'\n'"${why}"$'\n'
done < <(sort -u "$touched")

[[ -n "$red" ]] || exit 0
jq -n --arg r "Not committed: the project's gate (what CI runs) is red:"$'\n'"${red}Fix these, then commit." \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
