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
# GNU's stat, then BSD's
at=$(stat -c %Y "$first" 2>/dev/null || stat -f %m "$first" 2>/dev/null) || exit 0
(($(date +%s) - at >= 90)) || exit 0

door="${TMPDIR:-/tmp}/menard-door-$session"
# a session whose id changed under its server (`/clear`): the door is under the harness's pid too
p=$PPID
while [[ ! -r "$door" && -n "$p" && "$p" -gt 1 ]]; do
  [[ -r "${TMPDIR:-/tmp}/menard-door-$p" ]] && door="${TMPDIR:-/tmp}/menard-door-$p" && break
  p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
done
# A port that takes the connection is no server that answers: a wedged VM's kernel still accepts,
# and a server whose MCP session ended answers no hook. The door's greeting, then its `alive`
alive() {
  local port root token greeting answer
  { read -r port && read -r root && read -r token; } <"$1" || return 1
  [[ "$port" =~ ^[0-9]+$ ]] || return 1
  (
    exec 3<>"/dev/tcp/127.0.0.1/$port" || exit 1
    printf '%s\0' "$token" "$root" alive 0 0 >&3
    # 1 is a session that ended; a server older than `alive` answers that it has no such task, and is up
    read -t 2 -r greeting <&3 && read -t 2 -r answer <&3 && [[ "$greeting" == menard && -n "$answer" && "$answer" != 1 ]]
  ) 2>/dev/null
}
[[ -r "$door" ]] && alive "$door" && exit 0

touch "$said"
read -r -d '' ctx <<TEXT
menard's hooks server is not running in this session (its connection timed out at startup, or it stopped or stopped answering): no file is formatted after an edit, no script is refused, and menard's verbs run cold. Tell the user, once: /mcp, then reconnect plugin:menard:menard-hooks, restores it.
TEXT
jq -n --arg ctx "$ctx" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $ctx}}'
