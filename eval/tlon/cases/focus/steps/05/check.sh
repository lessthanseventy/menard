# step 05: server compiles clean, the hidden rename test and the whole suite pass, and no LeafWindow is left
set -uo pipefail
source "$EVAL_COMMON"
cd server
out=$(mix compile --warnings-as-errors 2>&1) || { echo "$out" | tail -20; echo "FAIL: compile"; exit 1; }
formatted_changes
# the module's name and its files, not a bare `leaf_window`: Server.Tmux.leaf_window?/1 is another
# function, the agent's to leave alone (focus2's all run was failed on it by an earlier version)
left=$(grep -rlw "LeafWindow" lib test --exclude-dir=hidden)
[ -z "$left" ] || { echo "FAIL: still named LeafWindow in: $left"; exit 1; }
for f in lib/server/leaf_window.ex test/server/leaf_window_test.exs; do
  [ ! -e "$f" ] || { echo "FAIL: $f is still there"; exit 1; }
done
out=$(mix test 2>&1); code=$?
echo "$out" | tail -15
[ $code -eq 0 ] || echo "FAIL: tests"
exit $code
