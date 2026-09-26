#!/usr/bin/env bash
# SessionStart (eval arm R): the project's modules and public functions, once, where the agent
# starts. Every eval trace opened with a grep and a Read to learn what is where; this is paid once
# and cached after. Uncapped: in focus1 a map showing a dozen functions of each module's 60-80
# answered little.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cwd=$(jq -r '.cwd // empty' <<<"$payload")
map=$(MENARD_CWD="${cwd:-$PWD}" "$menard" map --all 2>/dev/null </dev/null)
[[ -n "$map" ]] || exit 0
jq -n --arg ctx "The project's modules, their files and public functions (menard map):"$'\n'"$map" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
