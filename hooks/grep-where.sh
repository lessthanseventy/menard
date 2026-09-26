#!/usr/bin/env bash
# PostToolUse on Bash (eval arm G): a grep over Elixir files is answered with the function each hit
# sits in. Every eval trace ran a grep, then Read each hit's file to learn that; grep cannot say it.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cwd=$(jq -r '.cwd // empty' <<<"$payload")
out=$(jq -r '.tool_response.stdout // empty' <<<"$payload")
hits=$(grep -oE '^[^:[:space:]]+\.exs?:[0-9]+' <<<"$out" | head -40)
[[ -n "$hits" ]] || exit 0
# shellcheck disable=SC2086
where=$(MENARD_CWD="${cwd:-$PWD}" "$menard" where $hits 2>/dev/null </dev/null)
[[ -n "$where" ]] || exit 0
jq -n --arg ctx "The function each Elixir hit is in (menard where):"$'\n'"$where" \
  '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $ctx}}'
