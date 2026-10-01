#!/usr/bin/env bash
# Before and after a run: its test database dropped (only a name agent_env.sh makes, oban_test_*;
# a connection still on it terminated with it). `fresh` (a run starts, or a step is redone): then a
# new one, cloned from the template's, migrated. A failure is said and fails the script.
# Args: RID WS [fresh] (the env from agent_env.sh is set)
db=${POSTGRES_URL#*localhost/}
db=${db%%\?*}
[[ "$db" == oban_test_?* ]] || { echo "cleanup: not a run's database: $db"; exit 1; }
PGOPTIONS="-c client_min_messages=warning" dropdb -h /run/postgresql --force --if-exists "$db" || exit 1
[[ "${3:-}" == fresh ]] || exit 0
createdb -h /run/postgresql -T oban_eval_template "$db"
