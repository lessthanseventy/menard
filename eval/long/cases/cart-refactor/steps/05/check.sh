source "$EVAL_COMMON"
compiles
# a test that calls receipt, beyond those the fixture started with (hidden ones don't count)
before=$(git grep -c "receipt(" eval-base -- test | awk -F: '{s+=$NF} END {print s+0}')
after=$(grep -rc --exclude-dir=hidden "receipt(" test | awk -F: '{s+=$NF} END {print s+0}')
[ "$after" -gt "$before" ] || fail "no new test calls receipt ($before before, $after now)"
tests_pass
formatted
