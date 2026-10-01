# A step of a replayed history (eval/upstream): compiles clean; the commit's own tests (hidden/,
# copied in, `deleted` removed) and the rest of the suite green. MySQL's tests are left out (no MySQL
# here). A run red only on timing (the suite's assert_receive under load) gets one rerun of what
# failed, noted.
set -uo pipefail
source "$EVAL_COMMON"
[ -f "$CASE_DIR/deleted" ] && xargs -r rm -f < "$CASE_DIR/deleted"
compiles
upstream_formatted
upstream_tests
