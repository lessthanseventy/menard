# step 03: cockpit.ex is split for real (split.py, against the eval-base tag: its code lines at most
# 60% of before, at least two new modules of substance under lib/console/cockpit/ that cockpit.ex
# uses, the code moved and not deleted), console compiles clean, formatted and credo --strict
# clean, every public function of Console.Cockpit that is not a GenServer callback is still there
# (the hidden API test), and the whole console suite passes. Line count alone passed a comment
# purge (cockpit.ex was 1,775 lines, 451 of them comments); the tests alone pass one dump module.
set -uo pipefail
source "$EVAL_COMMON"
python3 "$CASE_DIR/split.py" || exit 1
cd console
out=$(mix compile --warnings-as-errors 2>&1) || { echo "$out" | tail -20; echo "FAIL: compile"; exit 1; }
formatted_changes
out=$(mix credo --strict 2>&1) || { echo "$out" | tail -15; echo "FAIL: credo --strict"; exit 1; }
out=$(mix test 2>&1); code=$?
echo "$out" | tail -15
[ $code -eq 0 ] || echo "FAIL: tests"
exit $code
