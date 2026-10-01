#!/usr/bin/env bash
# The format hook for a harness that runs a command (docs/adapters.md): the payload on stdin goes
# to `menard hook` (Menard.Hook), which formats every Elixir file the call wrote and says what the
# formatter changed. Claude Code reaches the same code in the MCP server already running
# (hooks/hooks.json, `mcp_tool`), with no VM to start.
set -uo pipefail
menard="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/bin/menard"
payload=$(cat)
out=$(printf '%s' "$payload" | "$menard" hook)
status=$?

# Run under Claude Code (it sets CLAUDE_PLUGIN_ROOT for a plugin's command hooks), this script is
# wiring that hooks.json no longer has: the process started before it changed, and keeps it until
# it restarts (2026-09-30: a session started 09-26 had no MCP tools and no Read hook for days, and
# nothing said so). Said once a session, beside the hook's own answer.
if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
  session=$(jq -r '.session_id // "none"' <<<"$payload")
  mark="${TMPDIR:-/tmp}/menard-stale-wiring-${session//[^A-Za-z0-9_-]/}"
  if [[ ! -e "$mark" ]]; then
    : >"$mark"
    note="menard: this Claude Code process runs menard's hooks as they were wired when it started, not as the plugin wires them now (MCP tools, the Read hook). Ask the user to restart Claude Code."
    event=$(jq -r '.hook_event_name // "PostToolUse"' <<<"$payload")
    # the hook's own answer stands where it is not JSON to add to
    merged=$(jq -cn --arg e "$event" --arg n "$note" --argjson o "${out:-"{}"}" \
      '$o * {hookSpecificOutput: {hookEventName: $e, additionalContext: ((($o.hookSpecificOutput.additionalContext // "") + "\n" + $n) | ltrimstr("\n"))}}' 2>/dev/null) &&
      out=$merged
  fi
fi

printf '%s' "$out"
exit $status
