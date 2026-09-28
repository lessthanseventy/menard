#!/usr/bin/env bash
# The format hook for a harness that runs a command (docs/adapters.md): the payload on stdin goes
# to `menard hook` (Menard.Hook), which formats every Elixir file the call wrote and says what the
# formatter changed. Claude Code reaches the same code in the MCP server already running
# (hooks/hooks.json, `mcp_tool`), with no VM to start.
set -uo pipefail
menard="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/bin/menard"
exec "$menard" hook
