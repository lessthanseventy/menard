# A step of a replayed history (eval/upstream): compiles clean; the commit's own tests (hidden/,
# copied in, `deleted` removed) and the rest of the suite green, one rerun of what failed allowed
# and noted.
set -uo pipefail
source "$EVAL_COMMON"
[ -f "$CASE_DIR/deleted" ] && xargs -r rm -f < "$CASE_DIR/deleted"
compiles
upstream_formatted
upstream_tests
