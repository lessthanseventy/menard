# step 04: server compiles clean, then the hidden branches test with commits' own
set -uo pipefail
source "$EVAL_COMMON"
cd server
out=$(mix compile --warnings-as-errors 2>&1) || { echo "$out" | tail -20; echo "FAIL: compile"; exit 1; }
formatted_changes
out=$(mix test test/hidden/commits_branches_test.exs test/server/commits_test.exs 2>&1); code=$?
echo "$out" | tail -15
[ $code -eq 0 ] || echo "FAIL: tests"

exit $code
