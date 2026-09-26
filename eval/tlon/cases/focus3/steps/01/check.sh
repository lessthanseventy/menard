# step 01: console compiles clean and formatted; the whole console suite, the hidden switcher test in it
set -uo pipefail
source "$EVAL_COMMON"
cd console
out=$(mix compile --warnings-as-errors 2>&1) || { echo "$out" | tail -20; echo "FAIL: compile"; exit 1; }
formatted_changes
out=$(mix test 2>&1); code=$?
echo "$out" | tail -15
[ $code -eq 0 ] || echo "FAIL: tests"
exit $code
