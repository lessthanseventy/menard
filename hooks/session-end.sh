#!/usr/bin/env bash
# SessionEnd: the session's marks in TMPDIR go with it (Menard.Hook does the same for the hooks
# server). Plain bash, not menard's start: a headless session cuts a SessionEnd hook short, menard's
# start is ~2 s, and the marks of the sessions it cut piled up in /tmp (7,664 by 2026-10-30)
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ -n "$session" && "$session" != none ]] || exit 0
rm -f "${TMPDIR:-/tmp}"/menard-*"$session"*
