# Sourced by each step's check.sh, in the workspace's copy: `hidden UPTO` puts the acceptance tests
# of steps 01..UPTO under test/hidden/ with the helper they share, as the app names things at that
# step (from step 08 a ticket moves by change_status/3, and the API test's moves name no agent,
# which both forms take). `graded` is what every step checks after: the project compiles clean,
# what the session wrote is formatted (a note, not a failure), and the whole suite passes, the
# session's own tests and the acceptance tests together.
set -uo pipefail
source "$EVAL_COMMON"
CASE=$(cd "$CASE_DIR/../.." && pwd)

hidden() {
  local upto=$1 version=v1 test
  ((10#$upto >= 8)) && version=v2
  mkdir -p test/hidden test/support
  cp "$CASE/tests/support/$version.ex" test/support/hidden.ex
  for test in "$CASE"/tests/[0-9][0-9]_*_test.exs; do
    local n=${test##*/}
    ((10#${n%%_*} <= 10#$upto)) && cp "$test" test/hidden/
  done
  return 0
}

graded() {
  local out code
  out=$(mix compile --warnings-as-errors 2>&1) || { echo "$out" | tail -20; echo "FAIL: compile"; exit 1; }
  formatted_changes
  out=$(mix test 2>&1); code=$?
  echo "$out" | tail -15
  [ $code -eq 0 ] || echo "FAIL: tests"
  exit $code
}
