# step 02: server compiles clean, then the hidden syntax test with search's own
set -uo pipefail
cd server
out=$(mix compile --warnings-as-errors 2>&1) || { echo "$out" | tail -20; echo "FAIL: compile"; exit 1; }
out=$(mix test test/hidden/search_syntax_test.exs test/server/search_test.exs 2>&1); code=$?
echo "$out" | tail -15
[ $code -eq 0 ] || echo "FAIL: tests"

exit $code
