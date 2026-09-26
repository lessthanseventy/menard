# step 03: console compiles clean, cockpit.ex is split (under 1,000 lines, from ~1,800), every public
# function of Console.Cockpit is still there (the hidden API test), and the whole console suite passes
set -uo pipefail
cd console
out=$(mix compile --warnings-as-errors 2>&1) || { echo "$out" | tail -20; echo "FAIL: compile"; exit 1; }
lines=$(wc -l < lib/console/cockpit.ex)
echo "cockpit.ex: $lines lines"
[ "$lines" -lt 1000 ] || { echo "FAIL: cockpit.ex is still $lines lines"; exit 1; }
out=$(mix test 2>&1); code=$?
echo "$out" | tail -15
[ $code -eq 0 ] || echo "FAIL: tests"
exit $code
