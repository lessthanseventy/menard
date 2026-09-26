#!/usr/bin/env bash
# PreToolUse on Read (eval arm big-read): a whole-file Read of an Elixir file over 800 lines is
# answered with the file's outline and a request for the lines needed. In the operator's sessions,
# 19 whole reads of big modules cost ~166k tokens, most of them one file read again and again. A
# second whole read of the same file goes through: an agent that needs it all is not trapped.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
file=$(jq -r '.tool_input.file_path // empty' <<<"$payload")
[[ "$file" == *.ex || "$file" == *.exs ]] || exit 0
[[ -f "$file" ]] || exit 0
[[ -z "$(jq -r '.tool_input.offset // .tool_input.limit // empty' <<<"$payload")" ]] || exit 0
lines=$(wc -l <"$file")
((lines > 800)) || exit 0

seen=$(session_file bigread)
grep -qxF "$file" "$seen" 2>/dev/null && exit 0
echo "$file" >>"$seen"

outline=$("$menard" outline "$file" 2>/dev/null </dev/null | tail -n +2)
[[ -n "$outline" ]] || exit 0
jq -n --arg r "${file##*/} is ${lines} lines. Each function and the lines it spans:"$'\n'"${outline}"$'\n'"Read the part you need with offset and limit; reading the whole file again is allowed if you really need it." \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
