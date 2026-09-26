#!/usr/bin/env bash
# After a run: its throwaway databases. Args: RID WS (the env from agent_env.sh is set)
for db in "${TLON_DATABASE:-}" "${TLON_TEST_DATABASE:-}"; do
  [[ "$db" == ev[dt]_* ]] && dropdb -h /run/postgresql --if-exists "$db" 2>/dev/null
done
# the run's tmux servers (agent_env.sh), then their directory
if [[ "${TMUX_TMPDIR:-}" == "$HOME/.cache/mt/"* ]]; then
  for sock in "$TMUX_TMPDIR"/tmux-*/*; do [[ -S "$sock" ]] && tmux -S "$sock" kill-server 2>/dev/null; done
  rm -rf "$TMUX_TMPDIR"
fi
exit 0
