#!/usr/bin/env bash
# Before and after a run: its two throwaway databases, a connection still on one terminated with
# it (--force). Only names agent_env.sh makes (a suffix after the project's own names) are ever
# dropped: the operator's ex_riverside_dev and ex_riverside_test are not of that shape. A drop that
# fails is reported and fails the script, not hidden: a database left behind is a rerun whose
# migrations start from the last run's state.
# Args: RID WS (the env from agent_env.sh is set)
status=0
for db in "ex_riverside_test${MIX_TEST_PARTITION:-}" "${EX_RIVERSIDE_DEV_DB:-}"; do
  [[ "$db" == ex_riverside_test_?* || "$db" == ex_riverside_dev_?* ]] || continue
  # no NOTICE for a database that is not there (the usual case before a run); a failure still prints
  PGOPTIONS="-c client_min_messages=warning" dropdb -h /run/postgresql --force --if-exists "$db" || status=1
done
exit $status
