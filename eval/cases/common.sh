# Sourced by every case's check.sh, which runs in the run's workspace after the agent is done,
# with the case's hidden/ files copied in. Exit 0 is a pass; say why on a failure.
set -uo pipefail

fail() { echo "FAIL: $*"; exit 1; }

compiles() {
  mix compile --warnings-as-errors --force >/tmp/.eval-compile.$$ 2>&1 || { tail -20 /tmp/.eval-compile.$$; fail "does not compile clean"; }
}

tests_pass() {
  out=$(mix test "$@" 2>&1) || { echo "$out" | tail -30; fail "mix test $*"; }
  echo "$out" | tail -1
}

# not a failure: recorded as the run's `formatted`, part of `clean`
formatted() {
  mix format --check-formatted >/dev/null 2>&1 || echo "NOTE: unformatted"
}
