source "$CASE_DIR/../common.sh"
compiles
[ -f test/shop/discounts_test.exs ] || fail "no test/shop/discounts_test.exs"
tests_pass
formatted
