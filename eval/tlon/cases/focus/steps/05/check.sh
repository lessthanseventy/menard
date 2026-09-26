# step 05: server compiles clean, the hidden rename test and the whole suite pass, and no LeafWindow is left
set -uo pipefail
cd server
out=$(mix compile --warnings-as-errors 2>&1) || { echo "$out" | tail -20; echo "FAIL: compile"; exit 1; }
left=$(grep -rln "LeafWindow\|leaf_window" lib test --exclude-dir=hidden)
[ -z "$left" ] || { echo "FAIL: still named LeafWindow in: $left"; exit 1; }
out=$(mix test 2>&1); code=$?
echo "$out" | tail -15
[ $code -eq 0 ] || echo "FAIL: tests"
exit $code
