#!/usr/bin/env bash
# SessionStart: what is so in this session, said before its first call (Menard.Scripts): under a ban
# on scripts in another language, that there is one, and what to use. A command hook, since the
# harness runs no mcp_tool hook at a session's start (the servers are not up yet). The ban is the
# one the plugin's MCP server runs under, read from the same place, so the two cannot differ; with
# none, nothing is started.
set -uo pipefail
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
set=$root/.claude-plugin/plugin.json
scripts=${MENARD_SCRIPTS:-$(jq -r '.mcpServers.menard.env.MENARD_SCRIPTS // "off"' "$set" 2>/dev/null)}
runs=${MENARD_RUNS:-$(jq -r '.mcpServers.menard.env.MENARD_RUNS // "off"' "$set" 2>/dev/null)}
case "$scripts.$runs" in narrow.* | full.* | *.rewrite) ;; *) exit 0 ;; esac
MENARD_SCRIPTS=$scripts MENARD_RUNS=$runs exec "$root/bin/menard" hook
