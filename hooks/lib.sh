# shellcheck shell=bash
# shellcheck disable=SC2034 # every variable here is read by the scripts that source this
# What the hooks share, sourced by each that needs it: the payload and its session, where menard
# is, where the session's state lives, what a search for written files skips, and a red reply put
# into lines for the agent. One copy, so a fix to one hook's copy cannot miss another's.

payload=$(cat)
session=$(jq -r '.session_id // "none"' <<<"$payload")
session=${session//[^A-Za-z0-9_-]/}

# the plugin's menard, else the one beside this checkout's hooks (a checkout has no plugin root,
# and a hook that looked only there did nothing); absolute, since some hooks hand it to the agent
menard="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/bin/menard"

# this session's file for NAME: the hooks' state across calls (touched projects, marks, counts)
session_file() { printf '%s/menard-%s-%s' "${TMPDIR:-/tmp}" "$1" "$session"; }

# find's arguments that skip what no one edits by hand: builds, deps, git's own files
prune=(\( -name _build -o -name deps -o -name .git -o -name node_modules \) -prune -o)

# a red reply (REPLY, menard's JSON line) as lines for the agent: its failures, else its tail, else
# menard's own refusal or error, which it writes to stderr (ERR, a file)
red_lines() {
  local why
  why=$(jq -r '(.failures // [])[:15][] | "  \(.kind) \(.at // "") \(.message | split("\n")[0])"' <<<"$1" 2>/dev/null)
  [[ -n "$why" ]] || why=$(jq -r '.tail // empty' <<<"$1" 2>/dev/null | tail -12)
  [[ -n "$why" ]] || why=$(tail -12 "$2")
  # nothing parsed, no tail, nothing on stderr (a run stopped under load): say so, and where its log
  # is, rather than a refusal with nothing under it
  if [[ -z "$why" ]]; then
    local log
    log=$(jq -r '.log // empty' <<<"$1" 2>/dev/null)
    why="  menard run check gave no answer it could read${log:+; its log: $log}"
  fi
  printf '%s' "$why"
}
