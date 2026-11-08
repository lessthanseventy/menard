#!/usr/bin/env bash
# UserPromptSubmit: a session whose hooks server is not running is told so, once. The server's
# connection timing out (30 s under the seats' load; three sessions in a month) left a session with
# no hooks and no word of it: nothing formatted after an edit, no script refused. The server leaves
# its door ($TMPDIR/menard-door-SESSION, Menard.Door) while it listens and takes it with it when it
# stops, so a door that answers is a server up, and a door whose port refuses is a server killed.
# The harness connects its servers at the first prompt, not at SessionStart, so the first prompt
# and the next 90 s say nothing.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ -n "$session" && "$session" != none ]] || exit 0
said=$(session_file hooks-down-said)
[[ -e "$said" ]] && exit 0
first=$(session_file first-prompt)
if [[ ! -e "$first" ]]; then
  touch "$first"
  exit 0
fi
(($(date +%s) - $(stat -c %Y "$first") >= 90)) || exit 0

door="${TMPDIR:-/tmp}/menard-door-$session"
if [[ -r "$door" ]]; then
  port=$(head -n1 "$door")
  [[ "$port" =~ ^[0-9]+$ ]] && (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null && exit 0
fi

touch "$said"
read -r -d '' ctx <<TEXT
menard's hooks server is not running in this session (its connection timed out at startup, or it stopped): no file is formatted after an edit, no script is refused, and menard's verbs run cold. Tell the user, once: /mcp, then reconnect plugin:menard:menard-hooks, restores it.
TEXT
jq -n --arg ctx "$ctx" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $ctx}}'
