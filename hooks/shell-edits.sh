#!/usr/bin/env bash
# Pre- and PostToolUse hook on Bash: the guard watches Edit/Write only (menard-only.sh says why),
# so `sed -i` or a script on a module goes unseen. This does not judge the command's text. Before
# it runs, a mark; after, any module under the project newer than the mark was changed by it, and
# the agent hears so, with the check that proves it still compiles.
#
# Advisory, never blocking: the command has already run.
set -uo pipefail

payload=$(cat)
[[ $(jq -r '.tool_name // empty' <<<"$payload" 2>/dev/null) == "Bash" ]] || exit 0
event=$(jq -r '.hook_event_name // empty' <<<"$payload")
session=$(jq -r '.session_id // "none"' <<<"$payload")
dir=$(jq -r '.cwd // empty' <<<"$payload")
dir=${dir:-${CLAUDE_PROJECT_DIR:-$PWD}}
p=${MENARD_TOOL_PREFIX:-mcp__plugin_menard_menard__}
mark="${TMPDIR:-/tmp}/menard-shell-edits-${session//[^A-Za-z0-9_-]/}"

if [[ "$event" == "PreToolUse" ]]; then
  touch "$mark"
  exit 0
fi

[[ -f "$mark" ]] || exit 0
cmd=$(jq -r '.tool_input.command // empty' <<<"$payload")
# menard's verbs, the formatter and git rewrite modules by design
grep -qE '(^|[[:space:];&|/])(menard|git)[[:space:]]|mix[[:space:]]+format' <<<"$cmd" && exit 0

changed=$(find "$dir" \( -name _build -o -name deps -o -name .git -o -name node_modules \) -prune -o \
  \( -name '*.ex' -o -name '*.exs' \) -newer "$mark" -print0 2>/dev/null |
  xargs -0 -r grep -lE '^[[:space:]]*defmodule\b' 2>/dev/null |
  while IFS= read -r f; do printf '%s\n' "${f#"$dir"/}"; done)
[[ -n "$changed" ]] || exit 0

cat >&2 <<MSG
menard: that command changed Elixir modules outside menard's verbs, with nothing parse-checked:
$(sed 's/^/  /' <<<"$changed")
Confirm they still compile: ${p}run {verb: "check"}. The next edit to a
module goes through menard's tools, which parse-check what they write.
MSG
exit 2
