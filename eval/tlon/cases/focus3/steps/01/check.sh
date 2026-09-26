# step 01: console compiles clean; the hidden switcher test with the picker's and fuzzy's own
set -uo pipefail
cd console
out=$(mix compile --warnings-as-errors 2>&1) || { echo "$out" | tail -20; echo "FAIL: compile"; exit 1; }
out=$(mix test test/hidden/switcher_titles_test.exs test/console/picker_test.exs test/console/fuzzy_test.exs 2>&1); code=$?
echo "$out" | tail -15
[ $code -eq 0 ] || echo "FAIL: tests"
exit $code
