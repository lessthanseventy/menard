#!/usr/bin/env bash
# SessionEnd: the session's marks in TMPDIR go with it (Menard.Hook). A command hook, with its own
# timeout: the harness cancels a SessionEnd hook past its short default, and menard's start is ~2 s
set -uo pipefail
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
exec "$root/bin/menard" hook
