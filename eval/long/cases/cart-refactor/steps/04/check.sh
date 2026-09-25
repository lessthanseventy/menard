source "$EVAL_COMMON"
compiles
grep -rq --exclude-dir=hidden "count_by_status" test || fail "no test for count_by_status"
# next to by_status/2: the def lands within 15 lines of it
a=$(grep -n "def by_status" lib/shop/orders.ex | head -1 | cut -d: -f1)
b=$(grep -n "def count_by_status" lib/shop/orders.ex | head -1 | cut -d: -f1)
[ -n "$b" ] && [ $(( a > b ? a - b : b - a )) -le 15 ] || fail "count_by_status is not next to by_status (lines $a, $b)"
tests_pass
formatted
