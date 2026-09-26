# step 01: compiles clean and formatted; the whole suite, the hidden review-queue test in it (the
# queue through the context function and the dashboard; the project's own permissions tests hold
# the strict-above rule against a "fix" that loosens it)
set -uo pipefail
source "$EVAL_COMMON"
out=$(mix compile --warnings-as-errors 2>&1) || { echo "$out" | tail -20; echo "FAIL: compile"; exit 1; }
formatted_changes
out=$(mix test 2>&1); code=$?
echo "$out" | tail -15
[ $code -eq 0 ] || echo "FAIL: tests"
exit $code
