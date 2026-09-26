# step 02: compiles clean and formatted; the whole suite, the hidden calendar tests in it (the file
# through its route: fields, escaping, UTC, CRLF, 404s, the page's link, Calendar.ics/1) and step
# 01's review-queue test still
set -uo pipefail
source "$EVAL_COMMON"
out=$(mix compile --warnings-as-errors 2>&1) || { echo "$out" | tail -20; echo "FAIL: compile"; exit 1; }
formatted_changes
out=$(mix test 2>&1); code=$?
echo "$out" | tail -15
[ $code -eq 0 ] || echo "FAIL: tests"
exit $code
