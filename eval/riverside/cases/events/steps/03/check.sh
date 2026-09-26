# step 03: events.ex is split for real (split.py, against the eval-base tag: its code lines at most
# 60% of before, at least two new modules of substance under lib/ex_riverside/events/ that events.ex
# uses, the code moved and not deleted), compiles clean, formatted and credo --strict clean (the
# base has no finding), every public function of ExRiverside.Events is still there (the hidden API
# test), and the whole suite passes, steps 01 and 02's hidden tests in it. Line count alone would
# pass a purge of docs, comments and blank lines (events.ex is 862 lines, 701 of them code); the
# tests alone pass one dump module.
set -uo pipefail
source "$EVAL_COMMON"
python3 "$CASE_DIR/split.py" || exit 1
out=$(mix compile --warnings-as-errors 2>&1) || { echo "$out" | tail -20; echo "FAIL: compile"; exit 1; }
formatted_changes
out=$(mix credo --strict 2>&1) || { echo "$out" | tail -15; echo "FAIL: credo --strict"; exit 1; }
out=$(mix test 2>&1); code=$?
echo "$out" | tail -15
[ $code -eq 0 ] || echo "FAIL: tests"
exit $code
