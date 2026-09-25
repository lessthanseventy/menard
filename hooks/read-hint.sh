#!/usr/bin/env bash
# PostToolUse hook on Read: a whole-file Read of a large module spends thousands of tokens that
# `outline` (every clause's name, head and lines) and a ranged Read answer with a fraction of.
# Nothing else steered agents there: in the eval they read a 1,016-line module whole.
#
# Advisory, never blocking: the Read has already happened.
set -uo pipefail

payload=$(cat)
[[ $(jq -r '.tool_name // empty' <<<"$payload" 2>/dev/null) == "Read" ]] || exit 0
file=$(jq -r '.tool_input.file_path // empty' <<<"$payload")
case "$file" in *.ex | *.exs) ;; *) exit 0 ;; esac
# a ranged Read already did what this would say
[[ $(jq -r '.tool_input.offset // .tool_input.limit // empty' <<<"$payload") == "" ]] || exit 0
[[ -f "$file" ]] && (($(wc -l <"$file") > 300)) || exit 0

cat >&2 <<MSG
menard: $(wc -l <"$file") lines read whole. Next time, mcp__plugin_menard_menard__outline {file} lists every
clause's name, head and lines in far fewer tokens; then Read only the lines you need (offset, limit).
MSG
exit 2
