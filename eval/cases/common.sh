# Sourced by every case's check.sh, which runs in the run's workspace after the agent is done,
# with the case's hidden/ files copied in. Exit 0 is a pass; say why on a failure.
set -uo pipefail

fail() { echo "FAIL: $*"; exit 1; }

compiles() {
  log=$(mktemp); mix compile --warnings-as-errors --force >"$log" 2>&1 || { tail -20 "$log"; rm -f "$log"; fail "does not compile clean"; }; rm -f "$log"
}

tests_pass() {
  out=$(mix test "$@" 2>&1) || { echo "$out" | tail -30; fail "mix test $*"; }
  echo "$out" | tail -1
}

# not a failure: recorded as the run's `formatted`, part of `clean`
formatted() {
  mix format --check-formatted >/dev/null 2>&1 || echo "NOTE: unformatted"
}

# the same over the files the run changed or added under the current directory only, the hidden/
# test files the check copied in (test/hidden/, acceptance/) left out (they are formatted to another project's rules): a
# whole-tree check trips on those, and on nothing the agent did
formatted_changes() {
  files=$({ git diff --name-only --relative --diff-filter=AM eval-base -- .; git ls-files -o --exclude-standard; } \
    | grep -E '\.(ex|exs|heex)$' | grep -vE '^(test/hidden|acceptance)/')
  # shellcheck disable=SC2086
  [ -z "$files" ] || mix format --check-formatted $files >/dev/null 2>&1 || echo "NOTE: unformatted"
}
