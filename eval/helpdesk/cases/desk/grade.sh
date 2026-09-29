# Sourced by each step's check.sh, in the workspace's copy.
#
# `hidden STEP` puts the step's own acceptance tests under test/hidden/, and those of the steps
# before it under acceptance/earlier/, with the helper they share, as the app names things at that
# step (from step 08 a ticket moves by change_status/3).
#
# `graded` is the verdict: the project compiles clean, what the session wrote is formatted (a
# note, not a failure), and the session's own tests and the step's acceptance tests pass. The
# earlier steps' acceptance tests are run after, and what they say is a note: desk1's with.2
# failed five steps on one assertion of step 05, and each of them read as a step not done.
# `graded all` holds the earlier ones to the verdict too: a refactor keeps everything.
set -uo pipefail
source "$EVAL_COMMON"
CASE=$(cd "$CASE_DIR/../.." && pwd)

hidden() {
  local step=$1 version=v1 test n
  ((10#$step >= 8)) && version=v2
  mkdir -p test/hidden acceptance/earlier test/support
  cp "$CASE/tests/support/$version.ex" test/support/hidden.ex
  for test in "$CASE"/tests/[0-9][0-9]_*_test.exs; do
    n=${test##*/}
    n=${n%%_*}
    if ((10#$n == 10#$step)); then cp "$test" test/hidden/; fi
    if ((10#$n < 10#$step)); then cp "$test" acceptance/earlier/; fi
  done
  return 0
}

graded() {
  local out code earlier=()
  out=$(mix compile --warnings-as-errors 2>&1) || { echo "$out" | tail -20; echo "FAIL: compile"; exit 1; }
  formatted_changes
  out=$(mix test 2>&1); code=$?
  echo "$out" | tail -15
  [ $code -eq 0 ] || echo "FAIL: tests"
  shopt -s nullglob
  earlier=(acceptance/earlier/*_test.exs)
  if ((${#earlier[@]})); then
    out=$(mix test "${earlier[@]}" 2>&1)
    if [ $? -eq 0 ]; then
      echo "NOTE: earlier steps' acceptance tests: green"
    else
      echo "$out" | grep -E "^ +[0-9]+\) test " | head -10
      echo "NOTE: earlier steps' acceptance tests: $(echo "$out" | grep -oE "[0-9]+ failures?" | tail -1)"
      if [ "${1:-}" = all ]; then echo "FAIL: earlier acceptance tests"; code=1; fi
    fi
  fi
  exit $code
}
