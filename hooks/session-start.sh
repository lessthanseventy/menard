#!/usr/bin/env bash
# SessionStart: what is so in this session, said before its first call (Menard.Scripts, Menard.Piped):
# no scripts in another language, menard's verbs when wanted, piped test runs run through menard. A
# command hook, since the harness runs no mcp_tool hook at a session's start (the servers are not up
# yet).
# A fresh install or an update builds menard first, past the hook's timeout: the session would
# start with none of it said. Then the text is said from hooks/upfront.txt, kept equal by a test.
set -uo pipefail
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
payload=$(cat)
timeout 20 "$root/bin/menard" hook <<<"$payload" && exit 0

[[ -n "${CLAUDE_ENV_FILE:-}" ]] && printf "export PATH=\"%s:\$PATH\"\n" "$root/bin" >>"$CLAUDE_ENV_FILE"
jq -n --rawfile ctx "$root/hooks/upfront.txt" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
