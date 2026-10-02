#!/usr/bin/env bash
# SessionStart: what is so in this session, said before its first call (Menard.Scripts, Menard.Piped):
# no scripts in another language, menard's verbs when wanted, piped test runs run through menard. A
# command hook, since the harness runs no mcp_tool hook at a session's start (the servers are not up
# yet).
set -uo pipefail
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
exec "$root/bin/menard" hook
