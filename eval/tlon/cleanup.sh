#!/usr/bin/env bash
# After a run: its throwaway databases. Args: RID WS (the env from agent_env.sh is set)
for db in "${TLON_DATABASE:-}" "${TLON_TEST_DATABASE:-}"; do
  [[ "$db" == ev[dt]_* ]] && dropdb -h /run/postgresql --if-exists "$db" 2>/dev/null
done
exit 0
