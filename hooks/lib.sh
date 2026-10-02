# shellcheck shell=bash
# shellcheck disable=SC2034 # every variable here is read by the scripts that source this
# What the hooks share, sourced by each that needs it: the payload and its session, where menard
# is, where the session's state lives, and what a search for written files skips. One copy, so a
# fix to one hook's copy cannot miss another's.

payload=$(cat)
session=$(jq -r '.session_id // "none"' <<<"$payload")
session=${session//[^A-Za-z0-9_-]/}

# the plugin's menard, else the one beside this checkout's hooks (a checkout has no plugin root,
# and a hook that looked only there did nothing); absolute, since some hooks hand it to the agent
menard="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/bin/menard"

# this session's file for NAME: the hooks' state across calls
session_file() { printf '%s/menard-%s-%s' "${TMPDIR:-/tmp}" "$1" "$session"; }

# find's arguments that skip what no one edits by hand: builds, deps, git's own files
prune=(\( -name _build -o -name deps -o -name .git -o -name node_modules \) -prune -o)
