# step 01: server compiles clean, then the hidden cursor test with attention's own
set -uo pipefail
source "$EVAL_COMMON"
cd server
out=$(mix compile --warnings-as-errors 2>&1) || { echo "$out" | tail -20; echo "FAIL: compile"; exit 1; }
formatted_changes
out=$(mix test test/hidden/attention_cursor_test.exs test/server/attention_test.exs 2>&1); code=$?
echo "$out" | tail -15
[ $code -eq 0 ] || echo "FAIL: tests"

exit $code
