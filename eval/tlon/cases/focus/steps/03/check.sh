# step 03: server compiles clean, then the whole server suite (the ticket is graded by review too)
set -uo pipefail
source "$EVAL_COMMON"
cd server
out=$(mix compile --warnings-as-errors 2>&1) || { echo "$out" | tail -20; echo "FAIL: compile"; exit 1; }
formatted_changes
out=$(mix test  2>&1); code=$?
echo "$out" | tail -15
[ $code -eq 0 ] || echo "FAIL: tests"

exit $code
