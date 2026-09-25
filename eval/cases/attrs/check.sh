source "$CASE_DIR/../common.sh"
compiles
grep -Eq '@open_statuses .*@statuses|@open_statuses\s*$' lib/shop/orders.ex || fail "@open_statuses is not derived from @statuses"
grep -Eq 'def open\?.*@open_statuses' lib/shop/orders.ex || grep -A3 'def open?' lib/shop/orders.ex | grep -q '@open_statuses' || fail "open?/1 does not use @open_statuses"
tests_pass
formatted
