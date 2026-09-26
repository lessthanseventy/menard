#!/usr/bin/env bash
# Before and after a run: its throwaway databases, a connection still on one terminated with it
# (--force). A drop that fails is reported and fails the script, not hidden: a database left behind
# is a rerun whose every test run fails (storage_up answers :already_up).
# Args: RID WS (the env from agent_env.sh is set)
status=0
for db in "${TLON_DATABASE:-}" "${TLON_TEST_DATABASE:-}"; do
  [[ "$db" == ev[dt]_* ]] || continue
  # no NOTICE for a database that is not there (the usual case before a run); a failure still prints
  PGOPTIONS="-c client_min_messages=warning" dropdb -h /run/postgresql --force --if-exists "$db" || status=1
done
# the run's tmux servers (agent_env.sh), then their directory
if [[ "${TMUX_TMPDIR:-}" == "$HOME/.cache/mt/"* ]]; then
  for sock in "$TMUX_TMPDIR"/tmux-*/*; do [[ -S "$sock" ]] && tmux -S "$sock" kill-server 2>/dev/null; done
  rm -rf "$TMUX_TMPDIR"
fi
exit $status
