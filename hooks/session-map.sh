#!/usr/bin/env bash
# SessionStart (eval arm R): the project's modules and public functions, once, where the agent
# starts. Every eval trace opened with a grep and a Read to learn what is where; this is paid once
# and cached after.
set -uo pipefail
cwd=$(jq -r '.cwd // empty')
map=$(MENARD_CWD="${cwd:-$PWD}" "${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/..}/bin/menard" map 2>/dev/null </dev/null)
[[ -n "$map" ]] || exit 0
jq -n --arg ctx "The project's modules, their files and public functions (menard map):"$'\n'"$map" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
